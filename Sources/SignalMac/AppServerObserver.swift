import Foundation
import SignalCore

public final class AppServerObserver {
    public var onEvent: ((TaskEvent) -> Void)?
    public var onStatus: ((String) -> Void)?
    private let queue = DispatchQueue(label: "local.codex-signal.observer")
    private var process: Process?
    private var input: FileHandle?
    private var buffer = LineBuffer()
    private var requests: [Int: (method: String, task: String?, revision: Int, at: Date)] = [:]
    private var revisions: [String: Int] = [:]
    private var nextID = 1
    private var generation = UUID()
    private var timer: DispatchSourceTimer?
    private var initialized = false
    private var reconnect: DispatchWorkItem?
    private var target: (binary: String, socket: String)?
    private var knownTasks = Set<String>()
    private var listedTasks = Set<String>()
    public let source = "codex-app-server"
    public init() {}

    private func status(_ value: String) { DispatchQueue.main.async { self.onStatus?(value) } }
    private func emit(_ event: TaskEvent) { DispatchQueue.main.async { self.onEvent?(event) } }

    public func start(binary: String, socket: String) {
        queue.async { self.startOnQueue(binary: binary, socket: socket) }
    }
    private func startOnQueue(binary: String, socket: String) {
        stopOnQueue()
        target = (binary, socket)
        guard !socket.isEmpty, FileManager.default.fileExists(atPath: socket),
              FileManager.default.isExecutableFile(atPath: binary) else {
            status("未连接：需要已有 app-server socket 和有效 Codex 路径"); return
        }
        generation = UUID(); let current = generation
        let process = Process(), output = Pipe(), input = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["app-server", "proxy", "--sock", socket]
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.queue.async { [weak self] in
                guard let self, self.generation == current else { return }
                if data.isEmpty { self.fail("观察连接已关闭"); return }
                do {
                    for line in try self.buffer.append(data) {
                        guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                        self.receive(message)
                    }
                } catch { self.fail("观察协议不兼容或消息超出限制") }
            }
        }
        process.terminationHandler = { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, self.generation == current else { return }
                self.fail("观察进程已退出")
            }
        }
        do { try process.run() } catch {
            output.fileHandleForReading.readabilityHandler = nil
            status("无法启动只读观察进程：\(error.localizedDescription)"); return
        }
        self.process = process; self.input = input.fileHandleForWriting
        send("initialize", params: ["clientInfo": ["name": "codex_signal", "version": "0.1.0"],
              "capabilities": ["experimentalApi": true]])
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.requests.values.contains(where: { Date().timeIntervalSince($0.at) > 12 }) {
                self.fail("观察健康检查超时"); return
            }
            if self.initialized && !self.requests.values.contains(where: { $0.method == "thread/loaded/list" }) {
                self.listedTasks.removeAll()
                self.send("thread/loaded/list", params: [:])
            }
        }
        self.timer = timer; timer.resume()
        status("正在连接已有 app-server…")
    }
    private func send(_ method: String, params: [String: Any], task: String? = nil) {
        let id = nextID; nextID += 1
        requests[id] = (method, task, task.flatMap { revisions[$0] } ?? 0, Date())
        write(["id": id, "method": method, "params": params])
    }
    private func write(_ message: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(10)
        do { try input?.write(contentsOf: data) } catch { fail("无法写入观察控制通道") }
    }
    private func receive(_ message: [String: Any]) {
        if let id = message["id"] as? Int, message["method"] == nil, let request = requests.removeValue(forKey: id) {
            if message["error"] != nil, request.method == "thread/read", let task = request.task {
                emit(TaskEvent(source: source, task: task, kind: .snapshot, phase: .unknown))
                return
            }
            guard message["error"] == nil, let result = message["result"] as? [String: Any] else {
                fail("服务器拒绝只读查询（版本或接口不兼容）"); return
            }
            switch request.method {
            case "initialize":
                initialized = true
                write(["method": "initialized"])
                send("thread/loaded/list", params: [:])
                status("实时观察已连接（仅此 app-server 承载的任务）")
            case "thread/loaded/list":
                guard let tasks = result["data"] as? [String] else { fail("任务列表格式不兼容"); return }
                listedTasks.formUnion(tasks)
                for task in tasks {
                    if !requests.values.contains(where: { $0.task == task }) {
                        send("thread/read", params: ["threadId": task, "includeTurns": false], task: task)
                    }
                }
                if let cursor = result["nextCursor"] as? String {
                    send("thread/loaded/list", params: ["cursor": cursor])
                } else {
                    for missing in knownTasks.subtracting(listedTasks) {
                        send("thread/read", params: ["threadId": missing, "includeTurns": false], task: missing)
                    }
                    knownTasks = listedTasks
                }
            case "thread/read":
                guard let task = request.task, request.revision == (revisions[task] ?? 0),
                      let thread = result["thread"] as? [String: Any],
                      let rawStatus = thread["status"] as? [String: Any] else { return }
                emit(TaskEvent(source: source, task: task, kind: .snapshot,
                    title: thread["name"] as? String ?? task,
                    project: thread["cwd"] as? String,
                    phase: CodexAdapter.phase(status: rawStatus)))
            default: break
            }
            return
        }
        for event in CodexAdapter.events(message: message, source: source) {
            revisions[event.task, default: 0] += 1
            emit(event)
        }
    }
    private func fail(_ message: String) {
        stopOnQueue(); status(message + " · 5 秒后重连")
        guard let target else { return }
        let current = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == current else { return }
            self.startOnQueue(binary: target.binary, socket: target.socket)
        }
        reconnect = work
        queue.asyncAfter(deadline: .now() + 5, execute: work)
    }
    public func stop() { queue.async { self.stopOnQueue(); self.status("实时观察已停止") } }
    private func stopOnQueue() {
        reconnect?.cancel(); reconnect = nil
        generation = UUID(); timer?.cancel(); timer = nil
        if process != nil { emit(TaskEvent(source: source, kind: .disconnected)) }
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        try? input?.close()
        process = nil; input = nil; initialized = false; requests.removeAll(); revisions.removeAll(); buffer = LineBuffer()
        listedTasks.removeAll(); knownTasks.removeAll()
    }
}

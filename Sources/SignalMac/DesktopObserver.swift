import Foundation
import Network
import Darwin
import SignalCore

public final class DesktopObserver {
    public var onEvent: ((TaskEvent) -> Void)?
    public var onStatus: ((String) -> Void)?
    public let source = "codex-desktop"
    private let queue = DispatchQueue(label: "local.codex-signal.desktop")
    private var connection: NWConnection?
    private var timer: DispatchSourceTimer?
    private var generation = UUID()
    private var home = ""
    private var clientID: String?
    private var initializeID = ""
    private var deadline = Date.distantFuture
    private var nextScan = Date.distantPast
    private var buffer = DesktopFrameBuffer()
    private var entries: [String: HistoryEntry] = [:]
    private var states: [String: DesktopState] = [:]
    private var owners: [String: String] = [:]
    private var pending: [String: Date] = [:]
    private var failedSubscriptions = Set<String>()
    private var lastStatus = ""
    private let listEntries: (String) throws -> [HistoryEntry]

    public init(listEntries: @escaping (String) throws -> [HistoryEntry] = { try HistoryReader.read(home: $0, limit: 100) }) {
        self.listEntries = listEntries
    }

    private func status(_ value: String) {
        guard value != lastStatus else { return }
        lastStatus = value
        DispatchQueue.main.async { self.onStatus?(value) }
    }

    private func emit(task: String, phase: TaskPhase) {
        let entry = entries[task]
        let event = TaskEvent(source: source, task: task, kind: .snapshot, title: entry?.title, project: entry?.project, phase: phase)
        DispatchQueue.main.async { self.onEvent?(event) }
    }

    public func start(home: String) {
        queue.async {
            self.stopOnQueue()
            self.home = home
            self.connect()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    public func stop() {
        queue.async { self.stopOnQueue(); self.status("实时观察已停止") }
    }

    private func connect() {
        let path = URL(fileURLWithPath: home).appendingPathComponent("ipc/ipc.sock").path
        var socketInfo = stat(), directoryInfo = stat()
        guard lstat(path, &socketInfo) == 0 else {
            status("未发现 Desktop IPC：\(path) · 请启动 Codex Desktop，5 秒后重试")
            deadline = Date().addingTimeInterval(5)
            return
        }
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        guard socketInfo.st_mode & S_IFMT == S_IFSOCK, socketInfo.st_uid == getuid(),
              lstat(directory, &directoryInfo) == 0, directoryInfo.st_mode & S_IFMT == S_IFDIR,
              directoryInfo.st_uid == getuid(), directoryInfo.st_mode & 0o022 == 0 else {
            status("Desktop IPC 路径的类型、所有者或目录权限不符合要求 · 5 秒后重试")
            deadline = Date().addingTimeInterval(5)
            return
        }
        generation = UUID()
        let current = generation
        let connection = NWConnection(to: .unix(path: path), using: .tcp)
        self.connection = connection
        deadline = Date().addingTimeInterval(10)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, self.generation == current else { return }
            switch state {
            case .ready:
                self.initializeID = UUID().uuidString
                self.send(["type": "request", "requestId": self.initializeID, "method": "initialize",
                           "version": 0, "params": ["clientType": "codex-signal"]])
                self.read(current)
            case .failed(let error), .waiting(let error): self.fail("Desktop IPC 连接失败：\(error.localizedDescription)")
            default: break
            }
        }
        status("正在连接 Codex Desktop 本地 IPC…")
        connection.start(queue: queue)
    }

    private func read(_ current: UUID) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, finished, error in
            guard let self, self.generation == current else { return }
            do {
                if let data {
                    for frame in try self.buffer.append(data) {
                        guard let message = try JSONSerialization.jsonObject(with: frame) as? [String: Any] else {
                            throw SignalError.invalidEvent
                        }
                        try self.receive(message)
                        guard self.generation == current else { return }
                    }
                }
                if finished || error != nil { self.fail("Desktop IPC 已断开"); return }
                self.read(current)
            } catch { self.fail("Desktop 协议不兼容：\(error.localizedDescription)") }
        }
    }

    private func send(_ message: [String: Any]) {
        let current = generation
        do {
            let data = try DesktopFrameBuffer.encode(message)
            connection?.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self, self.generation == current, error != nil else { return }
                self.fail("无法发送 Desktop 只读订阅")
            })
        } catch { fail("Desktop 订阅消息编码失败") }
    }

    private func follow(_ task: String, enabled: Bool) {
        guard let clientID else { return }
        send(["type": "broadcast", "method": "thread-stream-following-changed", "sourceClientId": clientID,
              "version": 1, "params": ["conversationId": task, "hostId": "local", "following": enabled]])
        if enabled { pending[task] = Date() }
    }

    private func receive(_ message: [String: Any]) throws {
        if message["type"] as? String == "client-discovery-request", let request = message["requestId"] as? String {
            send(["type": "client-discovery-response", "requestId": request, "response": ["canHandle": false]])
            return
        }
        if message["type"] as? String == "response", message["requestId"] as? String == initializeID {
            guard message["resultType"] as? String == "success", message["method"] as? String == "initialize",
                  let result = message["result"] as? [String: Any], let client = result["clientId"] as? String,
                  !client.isEmpty else { throw SignalError.invalidResponse("Desktop 拒绝握手") }
            clientID = client
            deadline = .distantFuture
            nextScan = .distantPast
            status("Desktop IPC 已连接，正在发现任务…")
            tick()
            return
        }
        guard message["type"] as? String == "broadcast", let params = message["params"] as? [String: Any] else { return }
        switch message["method"] as? String {
        case "thread-stream-state-changed":
            guard params["hostId"] as? String == "local", let task = params["conversationId"] as? String,
                  entries[task] != nil else { return }
            guard message["version"] as? Int == 11 else { throw SignalError.invalidResponse("仅支持 Desktop 状态协议 v11") }
            guard let change = params["change"] as? [String: Any], let owner = message["sourceClientId"] as? String else {
                throw SignalError.invalidEvent
            }
            if let previous = owners[task], previous != owner {
                markLost(task)
                states.removeValue(forKey: task)
            }
            var state = states[task] ?? DesktopState()
            do {
                let changed = try state.apply(change)
                states[task] = state
                owners[task] = owner
                pending.removeValue(forKey: task)
                failedSubscriptions.remove(task)
                if changed { emit(task: task, phase: state.phase) }
                reportSubscriptions()
            } catch {
                markLost(task)
                states.removeValue(forKey: task)
                failedSubscriptions.insert(task)
                if pending[task] == nil { follow(task, enabled: false); follow(task, enabled: true) }
                status("Desktop 任务快照需要重新同步 · 正在重订阅")
            }
        case "thread-stream-following-status-requested":
            if params["hostId"] as? String == "local", let task = params["conversationId"] as? String, entries[task] != nil {
                follow(task, enabled: true)
            }
        case "client-status-changed":
            if params["status"] as? String == "disconnected", let owner = params["clientId"] as? String {
                for task in owners.filter({ $0.value == owner }).map(\.key) {
                    markLost(task)
                    states.removeValue(forKey: task); owners.removeValue(forKey: task)
                    failedSubscriptions.insert(task)
                    follow(task, enabled: true)
                }
                reportSubscriptions()
            }
        case "ipc-connection-reset": fail("Desktop IPC 要求重新连接")
        default: break
        }
    }

    private func markLost(_ task: String) {
        guard let phase = states[task]?.phase,
              [.working, .retrying, .waitingApproval, .waitingInput].contains(phase) else { return }
        emit(task: task, phase: .observerLost)
    }

    private func reportSubscriptions() {
        if states.isEmpty {
            status("Desktop IPC 已连接，尚未收到任务快照（候选 \(entries.count)，待响应 \(pending.count)）")
        } else {
            status("实时观察已连接 · Desktop · 已确认 \(states.count) 个任务，待响应 \(pending.count)\(failedSubscriptions.isEmpty ? "" : " · 部分任务正在重订阅")")
        }
    }

    private func tick() {
        if connection == nil {
            if Date() >= deadline { connect() }
            return
        }
        guard clientID != nil else {
            if Date() >= deadline { fail("Desktop IPC 握手超时") }
            return
        }
        if Date() >= nextScan {
            nextScan = Date().addingTimeInterval(5)
            do {
                let latest = try listEntries(home)
                for entry in latest {
                    let new = entries[entry.id] == nil
                    entries[entry.id] = entry
                    if new { follow(entry.id, enabled: true) }
                }
                let listed = Set(latest.map(\.id))
                for task in Array(entries.keys) where !listed.contains(task) {
                    if let phase = states[task]?.phase, [.working, .waitingApproval, .waitingInput].contains(phase) { continue }
                    follow(task, enabled: false)
                    entries.removeValue(forKey: task); states.removeValue(forKey: task)
                    owners.removeValue(forKey: task); pending.removeValue(forKey: task)
                    failedSubscriptions.remove(task)
                    emit(task: task, phase: .unknown)
                }
                reportSubscriptions()
            } catch { status("Desktop IPC 已连接，但任务发现失败：\(error.localizedDescription)") }
        }
        for task in Array(pending.keys) where Date().timeIntervalSince(pending[task]!) > 10 {
            if states[task] != nil { failedSubscriptions.insert(task) }
            markLost(task)
            states.removeValue(forKey: task)
            follow(task, enabled: false)
            follow(task, enabled: true)
            reportSubscriptions()
        }
    }

    private func closeConnection() {
        if connection != nil {
            let event = TaskEvent(source: source, kind: .disconnected)
            DispatchQueue.main.async { self.onEvent?(event) }
        }
        generation = UUID()
        connection?.stateUpdateHandler = nil
        connection?.cancel(); connection = nil
        clientID = nil; buffer = DesktopFrameBuffer()
        entries.removeAll(); states.removeAll(); owners.removeAll(); pending.removeAll(); failedSubscriptions.removeAll()
    }

    private func fail(_ message: String) {
        closeConnection()
        deadline = Date().addingTimeInterval(5)
        status(message + " · 5 秒后重连")
    }

    private func stopOnQueue() {
        timer?.cancel(); timer = nil
        closeConnection()
    }
}

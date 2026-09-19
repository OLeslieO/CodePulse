import Foundation
import SignalCore
import SignalMac
import Darwin

func usage() {
    print("""
    signalctl — Codex Signal 事件工具（不会自动安装 Codex hooks）
      emit SOURCE TASK KIND [--turn ID] [--request ID] [--title TEXT] [--project PATH] [--phase PHASE]
      bridge SOURCE          从 stdin 接收 Codex JSON-RPC 通知，发送心跳；EOF 发送断线
      replay FILE            离线回放标准事件 JSONL，打印最终状态，不触碰 LED
      demo                   向正在运行的应用发送 8 秒演示事件
      led-test               独立 LED 硬件自检；需先退出应用，约 11 秒，结束恢复系统灯
      desktop-check [秒数] [CODEX_HOME]  只读检查 Desktop 连接，默认 12 秒；不控灯
      history [CODEX_HOME]   只读查看最近任务元数据
      paths                  打印应用数据目录
    KIND: started retrying approvalRequested inputRequested requestResolved failed completed cancelled snapshot
    PHASE: unknown working retrying waitingApproval waitingInput interrupted observerLost finished
    """)
}

let args = Array(CommandLine.arguments.dropFirst())
do {
    guard let command = args.first else { usage(); exit(0) }
    switch command {
    case "desktop-check":
        guard args.count <= 3, let seconds = args.count > 1 ? Double(args[1]) : 12,
              seconds.isFinite, (1...60).contains(seconds) else { throw SignalError.invalidEvent }
        let home = args.count > 2 ? args[2] : Preferences.load().codexHome
        let observer = DesktopObserver()
        var phases: [String: TaskPhase] = [:]
        observer.onStatus = { print($0); fflush(stdout) }
        observer.onEvent = { event in
            guard event.kind == .snapshot, let phase = event.phase else { return }
            if phase != phases[event.task], [.working, .waitingApproval, .waitingInput, .interrupted, .observerLost].contains(phase) {
                print("\(event.task)：\(phase.label)"); fflush(stdout)
            }
            phases[event.task] = phase
        }
        observer.start(home: home)
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        observer.stop()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let confirmed = phases.values.filter { $0 != .unknown && $0 != .observerLost }.count
        print("检查结束：收到 \(phases.count) 个任务的状态，\(confirmed) 个状态已确认；未操作 LED")
        guard confirmed > 0 else { throw SignalError.io("未取得已确认的 Desktop 任务状态；请检查上面的连接诊断") }
    case "led-test":
        guard args.count == 1 else { throw SignalError.invalidEvent }
        try LEDHardwareTest.run { print($0); fflush(stdout) }
    case "paths": print(SignalPaths.root.path)
    case "emit":
        guard args.count >= 4, let kind = EventKind(rawValue: args[3]) else { throw SignalError.invalidEvent }
        var options: [String: String] = [:]
        let tail = Array(args.dropFirst(4))
        guard tail.count % 2 == 0 else { throw SignalError.invalidEvent }
        for i in stride(from: 0, to: tail.count, by: 2) {
            guard ["--turn", "--request", "--title", "--project", "--phase"].contains(tail[i]) else { throw SignalError.invalidEvent }
            options[tail[i]] = tail[i + 1]
        }
        try EventInbox.send(TaskEvent(source: args[1], task: args[2], kind: kind,
            turn: options["--turn"], request: options["--request"], title: options["--title"],
            project: options["--project"], phase: options["--phase"].flatMap(TaskPhase.init(rawValue:))))
        print("事件已投递（应用启动后消费；超过 30 秒的积压事件将被忽略）")
    case "replay":
        guard args.count == 2 else { throw SignalError.invalidEvent }
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: args[1])); defer { try? handle.close() }
        var lines = LineBuffer(maximum: 65536), engine = StateEngine()
        while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
            for line in try lines.append(chunk) { engine.apply(try EventCodec.decode(line)) }
        }
        for line in try lines.append(Data([10])) { engine.apply(try EventCodec.decode(line)) }
        print("LED: \(engine.mode.rawValue)")
        for row in engine.records.values.sorted(by: { $0.id < $1.id }) { print("\(row.id): \(row.phase.label)") }
    case "history":
        let home = args.count > 1 ? args[1] : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        for row in try HistoryReader.read(home: home) { print("\(row.title) | \(row.status) | tokens: \(row.tokens)") }
    case "bridge":
        guard args.count == 2 else { throw SignalError.invalidEvent }
        let source = args[1]
        let heartbeat = DispatchSource.makeTimerSource(queue: .global())
        heartbeat.schedule(deadline: .now(), repeating: 5)
        heartbeat.setEventHandler { try? EventInbox.send(TaskEvent(source: source, kind: .heartbeat)) }
        heartbeat.resume()
        defer { heartbeat.cancel(); try? EventInbox.send(TaskEvent(source: source, kind: .disconnected)) }
        var buffer = LineBuffer()
        while let chunk = try FileHandle.standardInput.read(upToCount: 65536), !chunk.isEmpty {
            for line in try buffer.append(chunk) {
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                for event in CodexAdapter.events(message: object, source: source) { try EventInbox.send(event) }
            }
        }
    case "demo":
        let source = "demo", task = UUID().uuidString
        print("演示将更新任务状态；若已启用 LED，也会控制灯。")
        for (kind, request) in [(EventKind.started, nil), (.approvalRequested, "approval-1"),
                                (.requestResolved, "approval-1"), (.completed, nil)] {
            try EventInbox.send(TaskEvent(source: source, task: task, kind: kind, request: request,
                title: "演示任务", project: "演示项目"))
            Thread.sleep(forTimeInterval: 2)
        }
    case "help", "--help": usage()
    default: usage(); exit(1)
    }
} catch {
    fputs("错误：\(error.localizedDescription)\n", stderr)
    exit(1)
}

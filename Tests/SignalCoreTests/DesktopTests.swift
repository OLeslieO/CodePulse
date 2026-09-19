import XCTest
import Foundation
import SignalCore
import SignalMac
import CSQLite

final class DesktopTests: XCTestCase {
    private func snapshot(_ revision: Int, type: String = "active", flags: [String] = [], methods: [String] = []) -> [String: Any] {
        ["type": "snapshot", "revision": revision, "conversationState": [
            "threadRuntimeStatus": ["type": type, "activeFlags": flags],
            "requests": methods.map { ["method": $0, "params": ["text": "reply approve and I will continue"]] },
            "turns": [["text": "reply approve and I will continue"]]
        ]]
    }

    private func patches(_ revision: Int, base: Int, _ changes: [[String: Any]]) -> [String: Any] {
        ["type": "patches", "revision": revision, "baseRevision": base, "patches": changes]
    }

    func testApprovalRemovalImmediatelyRestoresSolidAndCompletionTurnsOff() throws {
        var state = DesktopState(), engine = StateEngine()
        try state.apply(snapshot(1, flags: ["waitingOnApproval"], methods: ["item/commandExecution/requestApproval"]))
        engine.apply(TaskEvent(source: "desktop", task: "task", kind: .snapshot, phase: state.phase))
        XCTAssertEqual(engine.mode, .blink)
        try state.apply(patches(2, base: 1, [["op": "remove", "path": ["requests", 0]]]))
        engine.apply(TaskEvent(source: "desktop", task: "task", kind: .snapshot, phase: state.phase))
        XCTAssertEqual(engine.mode, .solid)
        try state.apply(patches(3, base: 2, [["op": "replace", "path": ["threadRuntimeStatus"], "value": ["type": "idle"]]]))
        engine.apply(TaskEvent(source: "desktop", task: "task", kind: .snapshot, phase: state.phase))
        XCTAssertEqual(engine.mode, .off)
    }

    func testTextDoesNotRequestApprovalAndStructuredInputDoes() throws {
        var state = DesktopState()
        try state.apply(snapshot(1, flags: ["waitingOnApproval"]))
        XCTAssertEqual(state.phase, .working)
        try state.apply(snapshot(2, flags: ["waitingOnUserInput"], methods: ["item/tool/requestUserInput"]))
        XCTAssertEqual(state.phase, .waitingInput)
        try state.apply(snapshot(3, flags: ["waitingOnApproval"], methods: ["mcpServer/elicitation/request"]))
        XCTAssertEqual(state.phase, .waitingInput)
        try state.apply(snapshot(4, flags: ["waitingOnApproval"], methods: ["item/permissions/requestApproval"]))
        XCTAssertEqual(state.phase, .waitingApproval)
    }

    func testNestedPatchesAndConcurrentRequests() throws {
        var state = DesktopState()
        try state.apply(snapshot(1))
        try state.apply(patches(2, base: 1, [
            ["op": "add", "path": ["threadRuntimeStatus", "activeFlags", 0], "value": "waitingOnApproval"],
            ["op": "add", "path": ["requests", 0], "value": ["method": "item/fileChange/requestApproval"]],
            ["op": "add", "path": ["requests", 1], "value": ["method": "item/tool/requestOptionPicker"]]
        ]))
        XCTAssertEqual(state.phase, .waitingApproval)
        try state.apply(patches(3, base: 2, [["op": "remove", "path": ["requests", 0]]]))
        XCTAssertEqual(state.phase, .waitingInput)
        try state.apply(patches(4, base: 3, [["op": "remove", "path": ["threadRuntimeStatus", "activeFlags", 0]]]))
        XCTAssertEqual(state.phase, .working)
    }

    func testStaleRevisionsIgnoredAndGapsRequireSnapshot() throws {
        var state = DesktopState()
        try state.apply(snapshot(5))
        XCTAssertFalse(try state.apply(snapshot(4, type: "idle")))
        XCTAssertThrowsError(try state.apply(patches(7, base: 6, [])))
        XCTAssertEqual(state.revision, 5)
        XCTAssertEqual(state.phase, .working)
        try state.apply(snapshot(8, type: "idle"))
        XCTAssertEqual(state.phase, .finished)
    }

    func testMalformedPatchCannotPartiallyClearAttention() throws {
        var state = DesktopState()
        try state.apply(snapshot(1, flags: ["waitingOnApproval"], methods: ["item/commandExecution/requestApproval"]))
        XCTAssertThrowsError(try state.apply(patches(2, base: 1, [
            ["op": "remove", "path": ["requests", 0]],
            ["op": "remove", "path": ["requests", 9]]
        ])))
        XCTAssertEqual(state.phase, .waitingApproval)
        XCTAssertEqual(state.revision, 1)
        XCTAssertThrowsError(try state.apply(snapshot(2, type: "futureUnknownType")))
    }

    func testRuntimeErrorAndObserverLossRemainDistinctFromIdle() throws {
        var state = DesktopState(), engine = StateEngine()
        try state.apply(snapshot(1))
        engine.apply(TaskEvent(source: "desktop", task: "active", kind: .snapshot, phase: state.phase))
        engine.apply(TaskEvent(source: "desktop", task: "idle", kind: .snapshot, phase: .finished))
        engine.disconnect(source: "desktop")
        XCTAssertEqual(engine.records["desktop:active"]?.phase, .observerLost)
        XCTAssertEqual(engine.records["desktop:idle"]?.phase, .finished)
        try state.apply(snapshot(2, type: "systemError"))
        XCTAssertEqual(state.phase, .interrupted)
        try state.apply(snapshot(3, type: "notLoaded"))
        XCTAssertEqual(state.phase, .unknown)
        engine.remove(source: "desktop")
        XCTAssertEqual(engine.mode, .off)
    }

    func testBinaryFramingHandlesSplitAndMultipleFrames() throws {
        let first = try DesktopFrameBuffer.encode(["method": "initialize"])
        let second = try DesktopFrameBuffer.encode(["version": 11])
        var buffer = DesktopFrameBuffer()
        XCTAssertTrue(try buffer.append(first.prefix(2)).isEmpty)
        let frames = try buffer.append(first.dropFirst(2) + second + first.prefix(3))
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: frames[0]) as? [String: String])?["method"], "initialize")
        XCTAssertEqual(try buffer.append(first.dropFirst(3)).count, 1)
        var invalid = DesktopFrameBuffer(maximum: 16)
        XCTAssertThrowsError(try invalid.append(Data([255, 255, 255, 127])))
    }

    func testMissingSocketReportsActionableStatus() throws {
        let observer = DesktopObserver()
        let missing = expectation(description: "missing socket")
        let stopped = expectation(description: "stop")
        observer.onStatus = {
            if $0.contains("未发现 Desktop IPC") { missing.fulfill() }
            if $0 == "实时观察已停止" { stopped.fulfill() }
        }
        observer.start(home: "/tmp/codex-signal-missing-" + UUID().uuidString)
        wait(for: [missing], timeout: 2)
        observer.stop()
        wait(for: [stopped], timeout: 2)
    }

    func testRealUnixTransportOnlySubscribesAndObservesOwnerDisconnect() throws {
        let directory = URL(fileURLWithPath: "/tmp").appendingPathComponent("desktop-fixture-" + UUID().uuidString)
        let ipc = directory.appendingPathComponent("ipc")
        try FileManager.default.createDirectory(at: ipc, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("state_5.sqlite").path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE threads(id TEXT,title TEXT,cwd TEXT,tokens_used INTEGER,updated_at INTEGER,archived INTEGER); INSERT INTO threads VALUES('fixture','Example','/tmp/project',0,1800000000,0);", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)
        let fixture = directory.appendingPathComponent("server.py")
        let script = #"""
        import json, socket, struct, sys, pathlib
        root = pathlib.Path(sys.argv[1])
        server = socket.socket(socket.AF_UNIX)
        try:
            server.bind(str(root / "ipc/ipc.sock"))
        except PermissionError:
            (root / "sandbox-blocked").touch()
            raise SystemExit(77)
        server.listen(1)
        server.settimeout(5)
        (root / "ready").touch()
        client, _ = server.accept()
        client.settimeout(5)
        def send(message):
            payload = json.dumps(message).encode()
            client.sendall(struct.pack("<I", len(payload)) + payload)
        def receive_exact(length):
            data = b""
            while len(data) < length:
                chunk = client.recv(length - len(data))
                if not chunk:
                    raise EOFError()
                data += chunk
            return data
        def snapshot(revision, flags, requests):
            send({"type":"broadcast", "method":"thread-stream-state-changed", "version":11, "sourceClientId":"owner",
                  "params":{"hostId":"local", "conversationId":"fixture", "change":{"type":"snapshot", "revision":revision,
                  "conversationState":{"threadRuntimeStatus":{"type":"active", "activeFlags":flags}, "requests":requests}}}})
        sent = False
        try:
            while True:
                length = struct.unpack("<I", receive_exact(4))[0]
                message = json.loads(receive_exact(length))
                method = message.get("method")
                if method == "initialize":
                    assert message["type"] == "request"
                    send({"type":"response", "requestId":message["requestId"], "method":"initialize", "resultType":"success", "result":{"clientId":"observer"}})
                    send({"type":"client-discovery-request", "requestId":"discover"})
                elif message.get("type") == "client-discovery-response":
                    assert message["response"] == {"canHandle":False}
                elif method == "thread-stream-following-changed":
                    assert message["params"]["hostId"] == "local"
                    assert message["sourceClientId"] == "observer"
                    if message["params"]["following"] and not sent:
                        sent = True
                        snapshot(1, [], [])
                        snapshot(2, ["waitingOnApproval"], [{"method":"item/commandExecution/requestApproval"}])
                        snapshot(3, [], [])
                        send({"type":"broadcast", "method":"client-status-changed", "params":{"clientId":"owner", "status":"disconnected"}})
                else:
                    raise AssertionError("unexpected write: " + str(method))
        except EOFError:
            (root / "passed").touch()
        finally:
            client.close()
            server.close()
        """#
        try Data(script.utf8).write(to: fixture)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [fixture.path, directory.path]
        try process.run()
        defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready").path), process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("sandbox-blocked").path) {
            throw XCTSkip("当前运行环境禁止绑定 Unix socket；请在普通终端运行此传输集成测试")
        }
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready").path) else {
            XCTFail("Unix socket fixture 启动失败"); return
        }
        let observer = DesktopObserver()
        let events = expectation(description: "working, approval, working, owner lost")
        let stopped = expectation(description: "observer stopped")
        var phases: [TaskPhase] = []
        observer.onEvent = { event in
            guard event.kind == .snapshot, let phase = event.phase else { return }
            phases.append(phase)
            if phases.count == 4 { events.fulfill() }
        }
        observer.onStatus = { if $0 == "实时观察已停止" { stopped.fulfill() } }
        observer.start(home: directory.path)
        wait(for: [events], timeout: 5)
        observer.stop()
        wait(for: [stopped], timeout: 2)
        XCTAssertEqual(phases, [.working, .waitingApproval, .working, .observerLost])
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("passed").path))
    }
}

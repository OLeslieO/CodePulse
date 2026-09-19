import XCTest
import Foundation
import Darwin
import CSQLite
import SignalCore
import SignalMac

final class IntegrationTests: XCTestCase {
    private var directory: URL!
    private var priorHome: String?

    override func setUpWithError() throws {
        priorHome = ProcessInfo.processInfo.environment["CODEX_SIGNAL_HOME"]
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-signal-test-" + UUID().uuidString)
        setenv("CODEX_SIGNAL_HOME", directory.path, 1)
        try SignalPaths.prepare()
    }

    override func tearDownWithError() throws {
        if let priorHome { setenv("CODEX_SIGNAL_HOME", priorHome, 1) } else { unsetenv("CODEX_SIGNAL_HOME") }
        try FileManager.default.removeItem(at: directory)
    }

    func testInboxIsOrderedAndDropsStaleAndMalformedEvents() throws {
        let now = Date()
        let earlier = TaskEvent(source: "fixture", task: "a", kind: .started, timestamp: now.addingTimeInterval(-0.2))
        let later = TaskEvent(source: "fixture", task: "a", kind: .completed, timestamp: now)
        try EventInbox.send(later); try EventInbox.send(earlier)
        try EventInbox.send(TaskEvent(source: "fixture", task: "old", kind: .started, timestamp: now.addingTimeInterval(-60)))
        try Data("broken".utf8).write(to: SignalPaths.inbox.appendingPathComponent("broken.json"))
        XCTAssertEqual(try EventInbox.drain().map(\.id), [earlier.id, later.id])
        XCTAssertTrue(try EventInbox.drain().isEmpty)
        let attrs = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testInboxDoesNotReadSymlinks() throws {
        let outside = directory.appendingPathComponent("outside.json")
        try EventCodec.encode(TaskEvent(source: "fixture", task: "outside", kind: .started)).write(to: outside)
        try FileManager.default.createSymbolicLink(at: SignalPaths.inbox.appendingPathComponent("link.json"), withDestinationURL: outside)
        XCTAssertTrue(try EventInbox.drain().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testSingleInstanceAndPreferencePersistence() throws {
        let first = try InstanceLock()
        try withExtendedLifetime(first) { XCTAssertThrowsError(try InstanceLock()) }
        var prefs = Preferences(); prefs.showMenu = false; prefs.blinkInterval = 0
        prefs.refreshInterval = 0; try prefs.save()
        let loaded = Preferences.load()
        XCTAssertFalse(loaded.showMenu); XCTAssertEqual(loaded.blinkInterval, 0.1)
        XCTAssertEqual(loaded.refreshInterval, 30)
    }

    func testHistoryDoesNotCreateMissingDatabase() {
        XCTAssertThrowsError(try HistoryReader.read(home: directory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("state_5.sqlite").path))
    }

    func testHistoryReadsMetadataWithoutClaimingLiveState() throws {
        func create(_ name: String, sql: String) throws {
            var db: OpaquePointer?
            XCTAssertEqual(sqlite3_open(directory.appendingPathComponent(name).path, &db), SQLITE_OK)
            defer { sqlite3_close(db) }
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        }
        try create("state_5.sqlite", sql: "CREATE TABLE threads(id TEXT,title TEXT,cwd TEXT,tokens_used INTEGER,updated_at INTEGER,archived INTEGER); INSERT INTO threads VALUES('a','Example','/tmp/project',123,1800000000,0);")
        try create("thread_history_1.sqlite", sql: "CREATE TABLE thread_turns(thread_id TEXT,status TEXT,rollout_ordinal INTEGER); INSERT INTO thread_turns VALUES('a','inProgress',1);")
        let rows = try HistoryReader.read(home: directory.path)
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows[0].tokens, 123)
        XCTAssertTrue(rows[0].status.contains("实时状态未确认"))
    }

    func testRetryAfterSupportsSecondsAndHTTPDate() {
        XCTAssertEqual(RetryDelay.parse("120"), 120)
        XCTAssertEqual(RetryDelay.parse("-1"), 0)
        XCTAssertNil(RetryDelay.parse("not a date"))
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-09-18T12:00:00Z")!
        XCTAssertEqual(RetryDelay.parse("Fri, 18 Sep 2026 12:01:00 GMT", now: now), 60)
    }

    func testHistoryPrefersNamesAndFiltersInternalAgents() throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("state_5.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE threads(id TEXT,title TEXT,name TEXT,source TEXT,cwd TEXT,tokens_used INTEGER,updated_at INTEGER,archived INTEGER);
        INSERT INTO threads VALUES('main','original long text','Renamed task','vscode','/tmp/project',123,1800000000,0);
        INSERT INTO threads VALUES('internal','Internal approval',NULL,'{"subagent":{"other":"guardian"}}','/tmp/project',1,1800000001,0);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        let rows = try HistoryReader.read(home: directory.path)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.title, "Renamed task")
    }

    func testObserverTranslatesRealProtocolShapesWithoutReplyingToApproval() throws {
        let fixture = directory.appendingPathComponent("mock-codex")
        let socket = directory.appendingPathComponent("fixture.sock")
        try Data().write(to: socket)
        let script = #"""
        #!/usr/bin/python3
        import json, sys
        for line in sys.stdin:
            message = json.loads(line)
            method = message.get("method")
            if method == "initialize":
                print(json.dumps({"id": message["id"], "result": {"userAgent": "fixture"}}), flush=True)
            elif method == "initialized":
                print(json.dumps({"method":"turn/started","params":{"threadId":"fixture","turn":{"id":"turn-1"}}}), flush=True)
                print(json.dumps({"id":"approval-1","method":"item/commandExecution/requestApproval","params":{"threadId":"fixture","turnId":"turn-1"}}), flush=True)
                print(json.dumps({"method":"serverRequest/resolved","params":{"threadId":"fixture","requestId":"approval-1"}}), flush=True)
                print(json.dumps({"method":"error","params":{"threadId":"fixture","turnId":"turn-1","willRetry":True}}), flush=True)
                print(json.dumps({"method":"turn/completed","params":{"threadId":"fixture","turn":{"id":"turn-1","status":"completed"}}}), flush=True)
            elif method == "thread/loaded/list":
                print(json.dumps({"id":message["id"],"result":{"data":[],"nextCursor":None}}), flush=True)
            else:
                sys.exit(17)
        """#
        try Data(script.utf8).write(to: fixture)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
        let observer = AppServerObserver()
        let received = expectation(description: "five protocol events")
        let stopped = expectation(description: "observer stopped")
        var kinds: [EventKind] = []
        observer.onEvent = { event in
            guard event.kind != .disconnected else { return }
            kinds.append(event.kind)
            if kinds.count == 5 { received.fulfill() }
        }
        observer.onStatus = { if $0 == "实时观察已停止" { stopped.fulfill() } }
        observer.start(binary: fixture.path, socket: socket.path)
        wait(for: [received], timeout: 5)
        observer.stop(); wait(for: [stopped], timeout: 2)
        XCTAssertEqual(kinds, [.started, .approvalRequested, .requestResolved, .retrying, .completed])
    }
}

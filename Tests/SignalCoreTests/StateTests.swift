import XCTest
import Foundation
import SignalCore

final class StateTests: XCTestCase {
    func event(_ kind: EventKind, task: String = "a", turn: String? = "t1", request: String? = nil,
               phase: TaskPhase? = nil, time: Double = 100) -> TaskEvent {
        TaskEvent(source: "test", task: task, kind: kind, turn: turn, request: request, phase: phase,
                  timestamp: Date(timeIntervalSince1970: time))
    }
    func testConcurrentRequestsAndTasks() {
        var state = StateEngine()
        state.apply(event(.started)); state.apply(event(.started, task: "b"))
        XCTAssertEqual(state.mode, .solid)
        state.apply(event(.approvalRequested, request: "one"))
        state.apply(event(.inputRequested, request: "two"))
        XCTAssertEqual(state.mode, .blink)
        state.apply(event(.requestResolved, request: "one"))
        XCTAssertEqual(state.records["test:a"]?.phase, .waitingInput)
        state.apply(event(.requestResolved, request: "two"))
        XCTAssertEqual(state.mode, .solid)
        state.apply(event(.completed)); XCTAssertEqual(state.mode, .solid)
        state.apply(event(.completed, task: "b")); XCTAssertEqual(state.mode, .off)
    }
    func testRetryAndTerminalErrorAcknowledgement() {
        var state = StateEngine()
        state.apply(event(.started)); state.apply(event(.retrying))
        XCTAssertEqual(state.mode, .solid)
        state.apply(event(.failed)); XCTAssertEqual(state.mode, .blink)
        state.acknowledge("test:a"); XCTAssertEqual(state.mode, .off)
        state.apply(event(.snapshot, phase: .interrupted))
        XCTAssertEqual(state.mode, .off)
        state.apply(event(.started, turn: "t2", time: 101)); XCTAssertEqual(state.mode, .solid)
    }
    func testDisconnectOnlyActiveAndSnapshotRecovery() {
        var state = StateEngine()
        state.apply(event(.completed, task: "idle")); state.apply(event(.started))
        state.disconnect(source: "test"); XCTAssertEqual(state.mode, .blink)
        XCTAssertEqual(state.records["test:idle"]?.phase, .finished)
        state.apply(event(.heartbeat)); XCTAssertEqual(state.mode, .blink)
        state.apply(event(.snapshot, phase: .working, time: Date().timeIntervalSince1970 + 1))
        XCTAssertEqual(state.mode, .solid)
    }
    func testOldTurnAndDuplicateCannotOverwriteNewRun() {
        var state = StateEngine()
        let first = event(.started)
        state.apply(first); state.apply(event(.completed, time: 101))
        state.apply(event(.started, turn: "t2", time: 102))
        state.apply(first); state.apply(event(.completed, time: 103))
        XCTAssertEqual(state.mode, .solid)
        state.apply(event(.failed, turn: "t2", time: 99))
        XCTAssertEqual(state.mode, .solid)
    }
    func testInvalidRequestAndTextIgnored() {
        var state = StateEngine(); state.apply(event(.started))
        state.apply(event(.approvalRequested)); XCTAssertEqual(state.mode, .solid)
        XCTAssertTrue(CodexAdapter.events(message: ["method": "item/agentMessage/delta",
            "params": ["threadId": "a", "delta": "reply approve and I will continue"]], source: "test").isEmpty)
        XCTAssertTrue(CodexAdapter.events(message: ["method": "item/autoApprovalReview/started", "params": ["threadId": "a"]], source: "test").isEmpty)
    }
    func testProtocolErrorsAreRetryAware() {
        for retry in [true, false] {
            let events = CodexAdapter.events(message: ["method": "error", "params": ["threadId": "a", "turnId": "t1", "willRetry": retry]], source: "test")
            XCTAssertEqual(events.first?.kind, retry ? .retrying : .failed)
        }
    }
    func testSnapshotFlagsAndTypedIDs() {
        XCTAssertEqual(CodexAdapter.phase(status: ["type": "active", "activeFlags": ["waitingOnApproval", "waitingOnUserInput"]]), .waitingApproval)
        XCTAssertEqual(CodexAdapter.phase(status: ["type": "active", "activeFlags": []]), .working)
        XCTAssertEqual(CodexAdapter.phase(status: ["type": "notLoaded"]), .unknown)
        XCTAssertNotEqual(CodexAdapter.requestID("12"), CodexAdapter.requestID(12))
    }
    func testCodecAndLineFraming() throws {
        let value = event(.started)
        let data = try EventCodec.encode(value)
        XCTAssertEqual(try EventCodec.decode(data), value)
        var lines = LineBuffer(maximum: 1000)
        XCTAssertTrue(try lines.append(data.prefix(5)).isEmpty)
        XCTAssertEqual(try lines.append(data.dropFirst(5) + Data([10])), [data])
        var small = LineBuffer(maximum: 2)
        XCTAssertThrowsError(try small.append(Data("xxxx".utf8)))
    }

    func testWaitingSnapshotDoesNotEraseKnownRequestIDs() {
        var state = StateEngine()
        state.apply(event(.started))
        state.apply(event(.approvalRequested, request: "one"))
        state.apply(event(.inputRequested, request: "two"))
        state.apply(event(.snapshot, phase: .waitingApproval))
        state.apply(event(.requestResolved, request: "one"))
        XCTAssertEqual(state.records["test:a"]?.phase, .waitingInput)
        state.apply(event(.requestResolved, request: "two"))
        XCTAssertEqual(state.mode, .solid)
    }

    func testErrorSurvivesIdleSnapshotUntilAcknowledged() {
        var state = StateEngine()
        state.apply(event(.started)); state.apply(event(.failed))
        state.apply(event(.snapshot, phase: .finished))
        XCTAssertEqual(state.mode, .blink)
        state.acknowledge("test:a")
        state.apply(event(.snapshot, phase: .finished))
        XCTAssertEqual(state.mode, .off)
        state.apply(event(.snapshot, phase: .working))
        XCTAssertEqual(state.mode, .solid)
    }

    func testUnknownActiveTaskIsObservationLossNotCompletion() {
        var state = StateEngine()
        state.apply(event(.snapshot, phase: .unknown))
        XCTAssertEqual(state.mode, .off)
        state.apply(event(.started))
        state.apply(event(.snapshot, phase: .unknown))
        XCTAssertEqual(state.records["test:a"]?.phase, .observerLost)
        XCTAssertEqual(state.mode, .blink)
    }

    func testCodecPreservesSubsecondOrderingAndReadsLegacyISO() throws {
        let first = event(.started, time: 1_800_000_000.123)
        let second = event(.completed, time: 1_800_000_000.456)
        let decodedFirst = try EventCodec.decode(EventCodec.encode(first))
        let decodedSecond = try EventCodec.decode(EventCodec.encode(second))
        XCTAssertLessThan(decodedFirst.timestamp, decodedSecond.timestamp)
        XCTAssertEqual(decodedFirst.timestamp.timeIntervalSince1970, first.timestamp.timeIntervalSince1970, accuracy: 0.000001)
        let json = #"{"id":"legacy","source":"test","task":"a","kind":"started","timestamp":"2026-09-18T12:00:00Z"}"#
        XCTAssertEqual(try EventCodec.decode(Data(json.utf8)).kind, .started)
    }

    func testMalformedCompletionCannotEndTask() {
        let message: [String: Any] = ["method": "turn/completed", "params": ["threadId": "a", "turn": ["id": "t1", "status": "unrecognized"]]]
        XCTAssertTrue(CodexAdapter.events(message: message, source: "test").isEmpty)
    }
}

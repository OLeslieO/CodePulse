import Foundation

public enum CodexAdapter {
    public static func phase(status: [String: Any]) -> TaskPhase {
        switch status["type"] as? String {
        case "idle": return .finished
        case "systemError": return .interrupted
        case "active":
            let flags = status["activeFlags"] as? [String] ?? []
            if flags.contains("waitingOnApproval") { return .waitingApproval }
            if flags.contains("waitingOnUserInput") { return .waitingInput }
            return .working
        default: return .unknown
        }
    }

    public static func events(message: [String: Any], source: String, now: Date = Date()) -> [TaskEvent] {
        guard let method = message["method"] as? String,
              let params = message["params"] as? [String: Any] else { return [] }
        let task = params["threadId"] as? String ?? ""
        let turn = params["turnId"] as? String
        func event(_ kind: EventKind, request: String? = nil, phase: TaskPhase? = nil) -> TaskEvent {
            TaskEvent(source: source, task: task, kind: kind, turn: turn, request: request,
                      phase: phase, timestamp: now)
        }
        switch method {
        case "thread/status/changed":
            guard let status = params["status"] as? [String: Any] else { return [] }
            return [event(.snapshot, phase: phase(status: status))]
        case "turn/started":
            var result = event(.started)
            result.turn = (params["turn"] as? [String: Any])?["id"] as? String
            return [result]
        case "turn/completed":
            guard let value = params["turn"] as? [String: Any], let status = value["status"] as? String,
                  ["completed", "failed", "interrupted"].contains(status) else { return [] }
            var result = event(status == "failed" ? .failed : .completed)
            result.turn = value["id"] as? String
            return [result]
        case "error":
            guard let retry = params["willRetry"] as? Bool else { return [] }
            return [event(retry ? .retrying : .failed)]
        case "serverRequest/resolved":
            guard let request = requestID(params["requestId"]) else { return [] }
            return [event(.requestResolved, request: request)]
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval", "item/permissions/requestApproval":
            guard let request = requestID(message["id"]) else { return [] }
            return [event(.approvalRequested, request: request)]
        case "item/tool/requestUserInput":
            guard let request = requestID(message["id"]) else { return [] }
            return [event(.inputRequested, request: request)]
        case "thread/closed":
            return [event(.snapshot, phase: .unknown)]
        case "thread/deleted", "thread/archived":
            return [event(.cancelled)]
        default: return []
        }
    }

    public static func requestID(_ value: Any?) -> String? {
        if let text = value as? String { return "s:" + text }
        if let number = value as? NSNumber { return "n:" + number.stringValue }
        return nil
    }
}

import Foundation

public struct DesktopState {
    public private(set) var revision: Int?
    private var methods: [String] = []
    private var runtime: [String: Any] = [:]
    public init() {}

    public var phase: TaskPhase {
        switch runtime["type"] as? String {
        case "systemError": return .interrupted
        case "idle": return .finished
        case "active":
            let flags = runtime["activeFlags"] as? [String] ?? []
            let approvals = ["item/commandExecution/requestApproval", "item/fileChange/requestApproval", "item/permissions/requestApproval"]
            let inputs = ["item/tool/requestUserInput", "item/tool/requestOptionPicker", "mcpServer/elicitation/request"]
            if flags.contains("waitingOnApproval") && methods.contains(where: approvals.contains) { return .waitingApproval }
            if flags.contains(where: { ["waitingOnUserInput", "waitingOnApproval"].contains($0) }),
               methods.contains(where: inputs.contains) { return .waitingInput }
            return .working
        default: return .unknown
        }
    }

    @discardableResult public mutating func apply(_ change: [String: Any]) throws -> Bool {
        guard let nextRevision = change["revision"] as? Int, nextRevision >= 0 else { throw SignalError.invalidEvent }
        if let revision, nextRevision <= revision { return false }
        var next = self
        switch change["type"] as? String {
        case "snapshot":
            guard let state = change["conversationState"] as? [String: Any],
                  let requests = state["requests"] as? [[String: Any]],
                  let runtime = state["threadRuntimeStatus"] as? [String: Any] else { throw SignalError.invalidEvent }
            next.methods = try requests.map(Self.method)
            next.runtime = runtime.filter { ["type", "activeFlags"].contains($0.key) }
        case "patches":
            guard let revision, change["baseRevision"] as? Int == revision,
                  let patches = change["patches"] as? [[String: Any]] else { throw SignalError.invalidEvent }
            for patch in patches { try next.patch(patch) }
        default: throw SignalError.invalidEvent
        }
        guard let type = next.runtime["type"] as? String,
              ["active", "idle", "notLoaded", "systemError"].contains(type),
              type != "active" || next.runtime["activeFlags"] is [String] else { throw SignalError.invalidEvent }
        next.revision = nextRevision
        self = next
        return true
    }

    private static func method(_ request: [String: Any]) throws -> String {
        guard let method = request["method"] as? String else { throw SignalError.invalidEvent }
        return method
    }

    private mutating func patch(_ patch: [String: Any]) throws {
        guard let path = patch["path"] as? [Any], let root = path.first as? String else { throw SignalError.invalidEvent }
        guard ["requests", "threadRuntimeStatus"].contains(root) else { return }
        guard let operation = patch["op"] as? String, ["add", "replace", "remove"].contains(operation) else {
            throw SignalError.invalidEvent
        }
        if root == "requests" {
            if path.count == 1 {
                guard operation != "remove", let requests = patch["value"] as? [[String: Any]] else { throw SignalError.invalidEvent }
                methods = try requests.map(Self.method)
            } else {
                guard let index = path[1] as? Int, index >= 0 else { throw SignalError.invalidEvent }
                if path.count == 2 {
                    if operation == "remove" {
                        guard index < methods.count else { throw SignalError.invalidEvent }
                        methods.remove(at: index)
                    } else {
                        guard let request = patch["value"] as? [String: Any] else { throw SignalError.invalidEvent }
                        let method = try Self.method(request)
                        if operation == "add" {
                            guard index <= methods.count else { throw SignalError.invalidEvent }
                            methods.insert(method, at: index)
                        } else {
                            guard index < methods.count else { throw SignalError.invalidEvent }
                            methods[index] = method
                        }
                    }
                } else if path[2] as? String == "method" {
                    guard path.count == 3, operation != "remove", index < methods.count,
                          let method = patch["value"] as? String else { throw SignalError.invalidEvent }
                    methods[index] = method
                }
            }
        } else if path.count == 1 {
            guard operation != "remove", let value = patch["value"] as? [String: Any] else { throw SignalError.invalidEvent }
            runtime = value.filter { ["type", "activeFlags"].contains($0.key) }
        } else if path.count == 2, let key = path[1] as? String, ["type", "activeFlags"].contains(key) {
            if operation == "remove" { runtime.removeValue(forKey: key) }
            else { runtime[key] = patch["value"] }
        } else if path.count == 3, path[1] as? String == "activeFlags",
                  let index = path[2] as? Int, index >= 0, var flags = runtime["activeFlags"] as? [String] {
            if operation == "remove" {
                guard index < flags.count else { throw SignalError.invalidEvent }
                flags.remove(at: index)
            } else {
                guard let value = patch["value"] as? String else { throw SignalError.invalidEvent }
                if operation == "add" {
                    guard index <= flags.count else { throw SignalError.invalidEvent }
                    flags.insert(value, at: index)
                } else {
                    guard index < flags.count else { throw SignalError.invalidEvent }
                    flags[index] = value
                }
            }
            runtime["activeFlags"] = flags
        } else { throw SignalError.invalidEvent }
    }
}

public struct DesktopFrameBuffer {
    private var data = Data()
    public let maximum: Int
    public init(maximum: Int = 32 * 1024 * 1024) { self.maximum = maximum }

    public mutating func append(_ chunk: Data) throws -> [Data] {
        data.append(chunk)
        var frames: [Data] = []
        var consumed = 0
        while data.count - consumed >= 4 {
            let start = data.startIndex + consumed
            let length = (0..<4).reduce(0) { $0 | (Int(data[start + $1]) << ($1 * 8)) }
            guard length > 0, length <= maximum else { throw SignalError.invalidResponse("Desktop 消息长度不兼容") }
            guard data.count - consumed >= length + 4 else { break }
            frames.append(data.subdata(in: (start + 4)..<(start + 4 + length)))
            consumed += length + 4
        }
        if consumed > 0 { data.removeFirst(consumed) }
        guard data.count <= maximum + 4 else { throw SignalError.invalidResponse("Desktop 消息超过限制") }
        return frames
    }

    public static func encode(_ message: [String: Any]) throws -> Data {
        let payload = try JSONSerialization.data(withJSONObject: message)
        guard payload.count <= 32 * 1024 * 1024 else { throw SignalError.invalidEvent }
        var length = UInt32(payload.count).littleEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(payload)
        return frame
    }
}

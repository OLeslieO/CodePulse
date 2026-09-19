import Foundation

public enum LEDMode: String, Codable { case off, solid, blink }

public enum TaskPhase: String, Codable {
    case unknown, working, retrying, waitingApproval, waitingInput, interrupted, observerLost, finished

    public var label: String {
        switch self {
        case .unknown: return "状态未确认"
        case .working: return "运行中"
        case .retrying: return "重试中"
        case .waitingApproval: return "等待审批"
        case .waitingInput: return "等待输入"
        case .interrupted: return "异常中断"
        case .observerLost: return "观察连接断开"
        case .finished: return "已结束"
        }
    }

    public var needsAttention: Bool {
        [.waitingApproval, .waitingInput, .interrupted, .observerLost].contains(self)
    }
}

public enum EventKind: String, Codable {
    case started, retrying, approvalRequested, inputRequested, requestResolved
    case failed, completed, cancelled, disconnected, snapshot, heartbeat
}

public struct TaskEvent: Codable, Equatable {
    public var id: String
    public var source: String
    public var task: String
    public var turn: String?
    public var kind: EventKind
    public var request: String?
    public var title: String?
    public var project: String?
    public var phase: TaskPhase?
    public var timestamp: Date

    public init(source: String, task: String = "", kind: EventKind, turn: String? = nil,
                request: String? = nil, title: String? = nil, project: String? = nil,
                phase: TaskPhase? = nil, id: String = UUID().uuidString, timestamp: Date = Date()) {
        self.id = id; self.source = source; self.task = task; self.kind = kind
        self.turn = turn; self.request = request; self.title = title; self.project = project
        self.phase = phase; self.timestamp = timestamp
    }

    public func validate() throws {
        guard !source.isEmpty, source.count <= 256, !id.isEmpty, id.count <= 256 else { throw SignalError.invalidEvent }
        guard [.disconnected, .heartbeat].contains(kind) || (!task.isEmpty && task.count <= 512) else {
            throw SignalError.invalidEvent
        }
        if [.approvalRequested, .inputRequested, .requestResolved].contains(kind), request?.isEmpty != false {
            throw SignalError.invalidEvent
        }
        if kind == .snapshot && phase == nil { throw SignalError.invalidEvent }
    }
}

public struct TaskRecord: Codable, Identifiable {
    public var id: String { source + ":" + task }
    public var source: String
    public var task: String
    public var turn: String?
    public var title: String
    public var project: String
    public var basePhase: TaskPhase
    public var pending: [String: TaskPhase] = [:]
    public var updatedAt: Date
    public var acknowledged = false
    public var retiredTurns: [String] = []

    public var phase: TaskPhase {
        if basePhase == .observerLost || basePhase == .interrupted { return basePhase }
        if pending.values.contains(.waitingApproval) { return .waitingApproval }
        if pending.values.contains(.waitingInput) { return .waitingInput }
        return basePhase
    }

    public var isRunning: Bool {
        [.working, .retrying, .waitingApproval, .waitingInput, .observerLost].contains(phase)
    }

    public var mode: LEDMode {
        if phase.needsAttention && !acknowledged { return .blink }
        if [.working, .retrying].contains(phase) { return .solid }
        return .off
    }
}

public struct StateEngine {
    public private(set) var records: [String: TaskRecord] = [:]
    private var seen = Set<String>()
    private var seenOrder: [String] = []

    public init() {}

    public var mode: LEDMode { mode(for: Array(records.values)) }

    public func mode(for selected: [TaskRecord]) -> LEDMode {
        if selected.contains(where: { $0.mode == .blink }) { return .blink }
        return selected.contains(where: { $0.mode == .solid }) ? .solid : .off
    }

    public mutating func apply(_ event: TaskEvent) {
        guard (try? event.validate()) != nil else { return }
        let eventKey = event.source + ":" + event.id
        guard seen.insert(eventKey).inserted else { return }
        seenOrder.append(eventKey)
        if seenOrder.count > 4096 { seen.remove(seenOrder.removeFirst()) }
        if event.kind == .heartbeat { return }
        if event.kind == .disconnected {
            for key in Array(records.keys) where records[key]?.source == event.source && records[key]?.isRunning == true {
                guard event.timestamp >= records[key]!.updatedAt else { continue }
                records[key]?.basePhase = .observerLost
                records[key]?.acknowledged = false
                records[key]?.updatedAt = event.timestamp
            }
            return
        }
        let key = event.source + ":" + event.task
        var record = records[key] ?? TaskRecord(source: event.source, task: event.task, turn: event.turn,
            title: event.title ?? event.task, project: event.project ?? "未分配项目",
            basePhase: .unknown, updatedAt: .distantPast)
        guard event.timestamp >= record.updatedAt else { return }
        if let turn = event.turn, record.retiredTurns.contains(turn) { return }
        if let turn = event.turn, turn != record.turn {
            guard [.started, .snapshot].contains(event.kind) || record.turn == nil else { return }
            if let previous = record.turn {
                record.retiredTurns.append(previous)
                record.retiredTurns = Array(record.retiredTurns.suffix(32))
            }
            record.turn = turn
            record.pending.removeAll()
            record.acknowledged = false
        }
        record.title = event.title ?? record.title
        record.project = event.project ?? record.project
        record.updatedAt = event.timestamp
        switch event.kind {
        case .started:
            record.basePhase = .working; record.pending.removeAll(); record.acknowledged = false
        case .retrying:
            record.basePhase = .retrying
        case .approvalRequested, .inputRequested:
            record.pending[event.request!] = event.kind == .approvalRequested ? .waitingApproval : .waitingInput
            if record.basePhase == .unknown { record.basePhase = .working }
            record.acknowledged = false
        case .requestResolved:
            let resolved = record.pending.removeValue(forKey: event.request!)
            if resolved != nil, record.pending.isEmpty,
               [.waitingApproval, .waitingInput].contains(record.basePhase) {
                record.basePhase = .working
            }
        case .failed:
            if record.basePhase != .interrupted { record.acknowledged = false }
            record.basePhase = .interrupted; record.pending.removeAll()
        case .completed, .cancelled:
            record.basePhase = .finished; record.pending.removeAll(); record.acknowledged = false
        case .snapshot:
            let next = event.phase!
            if record.basePhase == .interrupted && [.finished, .unknown].contains(next) { break }
            if next == .unknown && record.isRunning {
                record.basePhase = .observerLost; record.acknowledged = false; break
            }
            if record.basePhase != next { record.acknowledged = false }
            if [.waitingApproval, .waitingInput].contains(next), record.pending.values.contains(next) {
                record.basePhase = .working
            } else {
                record.basePhase = next; record.pending.removeAll()
            }
        case .disconnected, .heartbeat: break
        }
        records[key] = record
        if records.count > 500,
           let oldest = records.values.filter({ $0.mode == .off }).min(by: { $0.updatedAt < $1.updatedAt }) {
            records.removeValue(forKey: oldest.id)
        }
    }

    public mutating func acknowledge(_ id: String) {
        guard records[id]?.phase == .interrupted else { return }
        records[id]?.acknowledged = true
    }

    public mutating func disconnect(source: String) {
        apply(TaskEvent(source: source, kind: .disconnected))
    }

    public mutating func remove(source: String) {
        records = records.filter { $0.value.source != source }
    }
}

public enum SignalError: Error, LocalizedError {
    case invalidEvent, invalidConfiguration(String), invalidResponse(String), io(String)
    public var errorDescription: String? {
        switch self {
        case .invalidEvent: return "事件格式不完整或字段无效"
        case .invalidConfiguration(let message), .invalidResponse(let message), .io(let message): return message
        }
    }
}

public enum EventCodec {
    public static func encode(_ event: TaskEvent) throws -> Data {
        try event.validate()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(event)
    }

    public static func decode(_ data: Data) throws -> TaskEvent {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) { return Date(timeIntervalSince1970: value / 1000) }
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else { throw SignalError.invalidEvent }
            return date
        }
        let event = try decoder.decode(TaskEvent.self, from: data)
        try event.validate()
        return event
    }
}

import Foundation
import Darwin
import SignalCore

public enum SignalPaths {
    public static var root: URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_SIGNAL_HOME"], override.hasPrefix("/") {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexSignal", isDirectory: true)
    }
    public static var inbox: URL { root.appendingPathComponent("inbox", isDirectory: true) }
    public static func prepare() throws {
        for url in [root, inbox] {
            if FileManager.default.fileExists(atPath: url.path) {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                guard values.isSymbolicLink != true, values.isDirectory == true else {
                    throw SignalError.io("数据目录不是安全的普通目录")
                }
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                guard (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
                    throw SignalError.io("数据目录不属于当前用户")
                }
            } else {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    }
}

public struct Preferences: Codable {
    public var showMenu = true
    public var ledEnabled = false
    public var historyEnabled = true
    public var projectFilter = ""
    public var blinkInterval = 0.25
    public var refreshInterval = 60.0
    public var usageEnabled = false
    public var usage = UsageMapping()
    public var usageProvider: UsageProvider?
    public var packyAccount: PackyAccount?
    public var codexBinary = "/Applications/ChatGPT.app/Contents/Resources/codex"
    public var codexSocket = ""
    public var codexHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
    public init() {}

    public var selectedUsageProvider: UsageProvider {
        get { usageProvider ?? (usage.endpoint.isEmpty ? .packyCode : .customJSON) }
        set { usageProvider = newValue }
    }
    public var packySettings: PackyAccount {
        get { packyAccount ?? PackyAccount() }
        set { packyAccount = newValue }
    }
    public func usageCredentialAccount() throws -> String {
        switch selectedUsageProvider {
        case .packyCode: return try packySettings.credentialAccount()
        case .customJSON:
            _ = try usage.validatedURL()
            return usage.endpoint
        }
    }

    public static func load() -> Preferences {
        guard let data = try? Data(contentsOf: SignalPaths.root.appendingPathComponent("settings.json")),
              var result = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        result.blinkInterval = max(0.1, min(1, result.blinkInterval))
        result.refreshInterval = max(30, result.refreshInterval)
        return result
    }
    public func save() throws {
        try SignalPaths.prepare()
        let data = try JSONEncoder().encode(self)
        try data.write(to: SignalPaths.root.appendingPathComponent("settings.json"), options: .atomic)
    }
}

public final class InstanceLock {
    private var fd: Int32 = -1
    public init() throws {
        try SignalPaths.prepare()
        fd = open(SignalPaths.root.appendingPathComponent("app.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            if fd >= 0 { close(fd) }; fd = -1
            throw SignalError.io("Codex Signal 已运行，或无法取得单实例锁")
        }
    }
    deinit { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
}

public enum EventInbox {
    public static func send(_ event: TaskEvent) throws {
        try SignalPaths.prepare()
        let data = try EventCodec.encode(event)
        guard data.count <= 65536 else { throw SignalError.invalidEvent }
        let entries = try FileManager.default.contentsOfDirectory(atPath: SignalPaths.inbox.path)
        guard entries.count < 2000 else { throw SignalError.io("事件队列已满，请先启动应用") }
        try data.write(to: SignalPaths.inbox.appendingPathComponent(UUID().uuidString + ".json"), options: .atomic)
    }

    public static func drain() throws -> [TaskEvent] {
        let files = try FileManager.default.contentsOfDirectory(at: SignalPaths.inbox,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        var events: [TaskEvent] = []
        for file in files.filter({ $0.pathExtension == "json" }).prefix(500) {
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true else { continue }
            if (info.fileSize ?? Int.max) <= 65536,
               let data = try? Data(contentsOf: file), let event = try? EventCodec.decode(data),
               abs(event.timestamp.timeIntervalSinceNow) <= 30 {
                events.append(event)
            }
            try FileManager.default.removeItem(at: file)
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }
}

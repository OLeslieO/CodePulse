import Foundation

public struct UsageMapping: Codable, Equatable {
    public var endpoint = ""
    public var accountLabel = "Packy Code"
    public var balancePath = ""
    public var usedPath = ""
    public var limitPath = ""
    public var unit = ""
    public var scale = "1"
    public var periodLabel = ""
    public var authHeader = "Authorization"
    public var authPrefix = "Bearer "

    public init() {}

    public func validatedURL() throws -> URL {
        guard let url = URL(string: endpoint), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw SignalError.invalidConfiguration("请填写 HTTPS 查询地址；凭据不得放入 URL，第一版不支持查询参数")
        }
        guard !unit.trimmingCharacters(in: .whitespaces).isEmpty,
              !balancePath.isEmpty || (!usedPath.isEmpty && !limitPath.isEmpty),
              scale.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil,
              let divisor = Decimal(string: scale, locale: Locale(identifier: "en_US_POSIX")), divisor > 0 else {
            throw SignalError.invalidConfiguration("需要单位、有效字段路径及大于零的换算除数")
        }
        guard ["Authorization", "X-API-Key"].contains(authHeader),
              !authPrefix.contains("\r"), !authPrefix.contains("\n") else {
            throw SignalError.invalidConfiguration("认证头只支持 Authorization 或 X-API-Key")
        }
        if !usedPath.isEmpty || !limitPath.isEmpty {
            guard !usedPath.isEmpty, !limitPath.isEmpty, !periodLabel.isEmpty else {
                throw SignalError.invalidConfiguration("使用比例需要已用、总额和周期说明")
            }
        }
        return url
    }
}

public struct UsageSnapshot: Codable, Equatable {
    public var account: String
    public var balance: Decimal?
    public var used: Decimal?
    public var limit: Decimal?
    public var unit: String
    public var period: String
    public var fetchedAt: Date
    public var origin: String

    public var ratio: Decimal? {
        guard let used, let limit, limit > 0 else { return nil }
        return used / limit
    }

    public static func parse(_ data: Data, mapping: UsageMapping, now: Date = Date()) throws -> UsageSnapshot {
        _ = try mapping.validatedURL()
        let object = try JSONSerialization.jsonObject(with: data)
        let divisor = Decimal(string: mapping.scale, locale: Locale(identifier: "en_US_POSIX"))!
        func amount(_ path: String) throws -> Decimal? {
            if path.isEmpty { return nil }
            var value: Any = object
            for component in path.split(separator: ".") {
                guard let dictionary = value as? [String: Any], let next = dictionary[String(component)] else {
                    throw SignalError.invalidResponse("响应缺少字段：\(path)")
                }
                value = next
            }
            if value is NSNull { return nil }
            if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
                throw SignalError.invalidResponse("金额字段不能是布尔值：\(path)")
            }
            let text = (value as? String) ?? (value as? NSNumber)?.stringValue
            guard let text, let result = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
                  NSDecimalNumber(decimal: result) != .notANumber,
                  text.range(of: #"^-?\d+(\.\d+)?([eE][+-]?\d+)?$"#, options: .regularExpression) != nil else {
                throw SignalError.invalidResponse("金额字段不是有效数值：\(path)")
            }
            return result / divisor
        }
        let balance = try amount(mapping.balancePath)
        let used = try amount(mapping.usedPath)
        let limit = try amount(mapping.limitPath)
        guard balance != nil || used != nil else { throw SignalError.invalidResponse("响应中没有可用的余额或用量") }
        guard (used ?? 0) >= 0, (limit ?? 0) >= 0 else { throw SignalError.invalidResponse("已用或总额不能为负数") }
        return UsageSnapshot(account: mapping.accountLabel, balance: balance, used: used, limit: limit,
            unit: mapping.unit, period: mapping.periodLabel, fetchedAt: now, origin: mapping.endpoint)
    }
}

import CoreFoundation

public struct LineBuffer {
    private var bytes = Data()
    public let maximum: Int
    public init(maximum: Int = 1_048_576) { self.maximum = maximum }

    public mutating func append(_ chunk: Data) throws -> [Data] {
        bytes.append(chunk)
        var lines: [Data] = []
        while let newline = bytes.firstIndex(of: 10) {
            guard bytes.distance(from: bytes.startIndex, to: newline) <= maximum else {
                bytes.removeAll(); throw SignalError.io("事件行超过大小限制")
            }
            let line = Data(bytes[..<newline])
            bytes.removeSubrange(...newline)
            if !line.isEmpty { lines.append(line) }
        }
        if bytes.count > maximum { bytes.removeAll(); throw SignalError.io("未完成事件超过大小限制") }
        return lines
    }
}

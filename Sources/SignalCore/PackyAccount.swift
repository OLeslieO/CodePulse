import Foundation
import CoreFoundation

public enum UsageProvider: String, Codable, CaseIterable {
    case packyCode, customJSON
    public var label: String { self == .packyCode ? "PackyCode 账户余额" : "自定义 JSON 接口" }
}

public enum PackyAccountError: Error, LocalizedError {
    case rejected, identityMismatch
    public var errorDescription: String? {
        switch self {
        case .rejected: return "PackyCode 拒绝账户查询；请检查用户 ID 与账户访问令牌，推理 API Key 不能替代账户令牌"
        case .identityMismatch: return "返回的 PackyCode 账户与填写的用户 ID 不一致，未更新余额"
        }
    }
}

public struct PackyAccount: Codable, Equatable {
    public static let origins = ["https://www.packyapi.com", "https://www.packyapi.ai"]
    public var origin = "https://www.packyapi.com"
    public var userID = ""
    public var label = "PackyCode"
    public init() {}

    public func validatedUserID() throws -> String {
        let text = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
              let number = Int64(text), number > 0 else {
            throw SignalError.invalidConfiguration("请填写 PackyCode 账户的数字用户 ID，可从 All API Hub 的账号编辑页核对")
        }
        return String(number)
    }

    public func validatedURL() throws -> URL {
        guard Self.origins.contains(origin) else {
            throw SignalError.invalidConfiguration("请选择实际登录的 PackyCode 控制台域名；不使用推理接口地址")
        }
        _ = try validatedUserID()
        return URL(string: origin + "/api/user/self")!
    }

    public func credentialAccount() throws -> String {
        "packycode|\(try validatedURL().absoluteString)|\(try validatedUserID())"
    }

    public static func normalizedToken(_ token: String) throws -> String {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 8192,
              value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
            throw SignalError.invalidConfiguration("请填写账户访问令牌本身，不要包含 Bearer 前缀、Cookie 或换行")
        }
        return value
    }

    public func request(token: String) throws -> URLRequest {
        var request = URLRequest(url: try validatedURL(), cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.setValue("Bearer " + (try Self.normalizedToken(token)), forHTTPHeaderField: "Authorization")
        request.setValue(try validatedUserID(), forHTTPHeaderField: "New-API-User")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public func parse(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        let url = try validatedURL()
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = body["success"] as? NSNumber, CFGetTypeID(success) == CFBooleanGetTypeID() else {
            throw SignalError.invalidResponse("PackyCode 响应格式不兼容：缺少布尔 success 字段")
        }
        guard success.boolValue else { throw PackyAccountError.rejected }
        if let code = body["code"], !(code is NSNull) {
            let text = (code as? String) ?? (code as? NSNumber)?.stringValue
            guard text?.trimmingCharacters(in: .whitespacesAndNewlines) == "0" || text == "" else {
                throw PackyAccountError.rejected
            }
        }
        guard let account = body["data"] as? [String: Any] else {
            throw SignalError.invalidResponse("PackyCode 响应缺少账户 data")
        }
        func numberText(_ value: Any?) -> String? {
            if let number = value as? NSNumber {
                guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
                return number.stringValue
            }
            return value as? String
        }
        guard let identifier = numberText(account["id"]), let numericID = Int64(identifier), numericID > 0 else {
            throw SignalError.invalidResponse("PackyCode 响应缺少有效账户 ID")
        }
        guard String(numericID) == (try validatedUserID()) else { throw PackyAccountError.identityMismatch }
        guard let text = numberText(account["quota"]),
              text.range(of: #"^-?\d+(\.\d+)?([eE][+-]?\d+)?$"#, options: .regularExpression) != nil,
              let quota = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              NSDecimalNumber(decimal: quota) != .notANumber else {
            throw SignalError.invalidResponse("PackyCode 响应缺少有效的 data.quota；不会把未知余额显示为零")
        }
        let accountLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return UsageSnapshot(account: accountLabel.isEmpty ? "PackyCode" : accountLabel,
            balance: quota / Decimal(500_000), used: nil, limit: nil, unit: "USD", period: "账户余额",
            fetchedAt: now, origin: url.absoluteString)
    }
}

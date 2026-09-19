import Foundation
import Security
import SignalCore

public enum Credentials {
    private static let service = "local.codex-signal.usage"
    public static func set(_ value: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        if value.isEmpty {
            let result = SecItemDelete(query as CFDictionary)
            guard result == errSecSuccess || result == errSecItemNotFound else {
                throw SignalError.io("无法删除钥匙串凭据：\(result)")
            }
            return
        }
        let bytes = Data(value.utf8)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
        if result == errSecItemNotFound {
            var entry = query
            entry[kSecValueData as String] = bytes
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw SignalError.io("无法写入钥匙串") }
        } else if result != errSecSuccess { throw SignalError.io("无法更新钥匙串：\(result)") }
    }
    public static func get(account: String) throws -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SignalError.io("无法读取钥匙串：\(status)") }
        return String(data: data, encoding: .utf8)
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public struct UsageHTTPError: Error, LocalizedError {
    public let status: Int
    public let retryAfter: Double?
    public var errorDescription: String? { "用量接口 HTTP \(status)；保留上次成功数据" }
}

public enum RetryDelay {
    public static func parse(_ value: String?, now: Date = Date()) -> Double? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
}

public enum UsageClient {
    public static func fetch(mapping: UsageMapping) async throws -> UsageSnapshot {
        let url = try mapping.validatedURL()
        let token = try Credentials.get(account: mapping.endpoint)
        guard let token, !token.isEmpty, !token.contains("\n"), !token.contains("\r") else {
            throw SignalError.invalidConfiguration("请先保存该查询地址的认证凭据")
        }
        var request = URLRequest(url: url)
        request.setValue(mapping.authPrefix + token, forHTTPHeaderField: mapping.authHeader)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try UsageSnapshot.parse(await payload(request), mapping: mapping)
    }

    public static func fetchPacky(account: PackyAccount) async throws -> UsageSnapshot {
        guard let token = try Credentials.get(account: account.credentialAccount()), !token.isEmpty else {
            throw SignalError.invalidConfiguration("请在本地应用中保存此 PackyCode 账号的账户访问令牌")
        }
        let request = try account.request(token: token)
        return try account.parse(await payload(request))
    }

    static func payload(_ request: URLRequest, configuration: URLSessionConfiguration = .ephemeral) async throws -> Data {
        let config = configuration
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw SignalError.invalidResponse("响应不是 HTTP") }
        guard http.statusCode == 200 else {
            throw UsageHTTPError(status: http.statusCode, retryAfter: RetryDelay.parse(http.value(forHTTPHeaderField: "Retry-After")))
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1_048_576 else { throw SignalError.invalidResponse("用量响应超过 1 MB") }
            data.append(byte)
        }
        return data
    }
}

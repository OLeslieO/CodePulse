import XCTest
import Foundation
import SignalCore
@testable import SignalMac

private final class BalanceFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let status = Int(request.value(forHTTPHeaderField: "X-Fixture-Status") ?? "200") ?? 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json", "Retry-After": "120", "Location": "https://example.invalid/redirect"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let data = request.value(forHTTPHeaderField: "X-Fixture-Large") == "yes"
            ? Data(repeating: 32, count: 1_048_577)
            : Data(#"{"success":true,"data":{"id":42,"quota":1234567}}"#.utf8)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class PackyTests: XCTestCase {
    private func account() -> PackyAccount {
        var account = PackyAccount()
        account.userID = "42"
        return account
    }

    func testRequestUsesAccountEndpointBearerAndIdentityOnly() throws {
        let request = try account().request(token: "fixture-account-token")
        XCTAssertEqual(request.url?.absoluteString, "https://www.packyapi.com/api/user/self")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-account-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "New-API-User"), "42")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.url?.query)
    }

    func testQuotaConversionPreservesSmallAndNegativeBalancesWithoutInventingLimit() throws {
        for (quota, balance) in [("1234567", "2.469134"), ("1", "0.000002"), ("0", "0"), ("-1", "-0.000002")] {
            let result = try account().parse(Data("{\"success\":true,\"data\":{\"id\":42,\"quota\":\"\(quota)\",\"used_quota\":999999999}}".utf8))
            XCTAssertEqual(result.balance, Decimal(string: balance))
            XCTAssertEqual(result.unit, "USD")
            XCTAssertNil(result.used)
            XCTAssertNil(result.limit)
            XCTAssertNil(result.ratio)
        }
    }

    func testMissingInvalidOrBooleanQuotaNeverBecomesZero() throws {
        for value in ["null", "true", "\"12oops\"", "{}", "\"NaN\""] {
            XCTAssertThrowsError(try account().parse(Data("{\"success\":true,\"data\":{\"id\":42,\"quota\":\(value)}}".utf8)))
        }
        XCTAssertThrowsError(try account().parse(Data(#"{"success":true,"data":{"id":42}}"#.utf8)))
    }

    func testBusinessErrorAndIdentityMismatchDoNotPublishBalance() throws {
        for json in [#"{"success":false,"message":"fixture-account-token","data":{"id":42,"quota":100}}"#,
                     #"{"success":true,"code":401,"data":{"id":42,"quota":100}}"#,
                     #"{"success":true,"data":{"id":43,"quota":100}}"#] {
            XCTAssertThrowsError(try account().parse(Data(json.utf8))) { error in
                XCTAssertTrue(error is PackyAccountError)
                XCTAssertFalse(error.localizedDescription.contains("fixture-account-token"))
            }
        }
        for json in [#"{"data":{"id":42,"quota":100}}"#, #"{"success":1,"data":{"id":42,"quota":100}}"#,
                     #"{"success":true,"data":{"quota":100}}"#] {
            XCTAssertThrowsError(try account().parse(Data(json.utf8)))
        }
    }

    func testOnlySelectedConsoleOriginReceivesCredentials() throws {
        for origin in ["http://www.packyapi.com", "https://www.packyapi.com.evil.example", "https://www.packyapi.com/v1",
                       "https://www.packyapi.com?token=secret", "https://secret@www.packyapi.com", "https://cf.api.fan"] {
            var invalid = account(); invalid.origin = origin
            XCTAssertThrowsError(try invalid.request(token: "fixture-account-token"))
        }
        var alternate = account(); alternate.origin = "https://www.packyapi.ai"
        XCTAssertEqual(try alternate.request(token: "fixture-account-token").url?.host, "www.packyapi.ai")
    }

    func testCredentialValidationAndAccountStorageIsolation() throws {
        for token in ["", "Bearer token", "token\r\nInjected: yes", "token\u{0}value"] {
            XCTAssertThrowsError(try account().request(token: token))
        }
        for identifier in ["", "-1", "0", "42\r\nX-Test:1", "42.0"] {
            var invalid = account(); invalid.userID = identifier
            XCTAssertThrowsError(try invalid.validatedURL())
        }
        var another = account(); another.userID = "43"
        var otherOrigin = account(); otherOrigin.origin = "https://www.packyapi.ai"
        XCTAssertNotEqual(try account().credentialAccount(), try another.credentialAccount())
        XCTAssertNotEqual(try account().credentialAccount(), try otherOrigin.credentialAccount())
        var normalized = account(); normalized.userID = "0042"
        XCTAssertEqual(try account().credentialAccount(), try normalized.credentialAccount())
    }

    func testExistingPreferencesKeepLEDAndCustomUsageConfiguration() throws {
        var previous = Preferences()
        previous.ledEnabled = true
        previous.usage.endpoint = "https://example.com/balance"
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(previous)) as? [String: Any])
        json.removeValue(forKey: "usageProvider")
        json.removeValue(forKey: "packyAccount")
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(restored.ledEnabled)
        XCTAssertEqual(restored.selectedUsageProvider, .customJSON)
        XCTAssertEqual(restored.usage.endpoint, previous.usage.endpoint)
        XCTAssertEqual(Preferences().selectedUsageProvider, .packyCode)
        var updated = restored
        updated.selectedUsageProvider = .packyCode; updated.packySettings = account()
        let reloaded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(updated))
        XCTAssertEqual(reloaded.packySettings.userID, "42")
        XCTAssertEqual(reloaded.selectedUsageProvider, .packyCode)
        XCTAssertTrue(reloaded.ledEnabled)
    }

    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BalanceFixtureProtocol.self]
        return configuration
    }

    func testHTTPPayloadFeedsValidatedBalanceParserWithoutNetwork() async throws {
        let data = try await UsageClient.payload(account().request(token: "fixture-account-token"), configuration: configuration())
        XCTAssertEqual(try account().parse(data).balance, Decimal(string: "2.469134"))
    }

    func testHTTPFailuresAndRetryAfterArePreserved() async throws {
        for status in [302, 401, 403, 429, 503] {
            var request = try account().request(token: "fixture-account-token")
            request.setValue(String(status), forHTTPHeaderField: "X-Fixture-Status")
            do {
                _ = try await UsageClient.payload(request, configuration: configuration())
                XCTFail("Expected HTTP failure")
            } catch let error as UsageHTTPError {
                XCTAssertEqual(error.status, status)
                XCTAssertEqual(error.retryAfter, 120)
            }
        }
    }

    func testHTTPResponseSizeIsBounded() async throws {
        var request = try account().request(token: "fixture-account-token")
        request.setValue("yes", forHTTPHeaderField: "X-Fixture-Large")
        do {
            _ = try await UsageClient.payload(request, configuration: configuration())
            XCTFail("Expected response size failure")
        } catch { XCTAssertTrue(error.localizedDescription.contains("1 MB")) }
    }
}

import Testing
import Foundation
@testable import DLNAKit

@Suite("HTTPRetry")
struct HTTPRetryTests {
    @Test("接続系・タイムアウト系の URLError はリトライ対象")
    func retriable() {
        let codes: [URLError.Code] = [
            .notConnectedToInternet,   // -1009（再起動で直る症状の主因）
            .networkConnectionLost,    // -1005
            .timedOut,                 // -1001
            .cannotConnectToHost,      // -1004
            .cannotFindHost,           // -1003
            .dnsLookupFailed,          // -1006
        ]
        for code in codes {
            #expect(HTTPRetry.isRetriable(URLError(code)), "\(code) はリトライ対象であるべき")
        }
    }

    @Test("サーバー応答系・非ネットワークエラーはリトライ対象外")
    func nonRetriable() {
        #expect(!HTTPRetry.isRetriable(URLError(.badServerResponse)))
        #expect(!HTTPRetry.isRetriable(URLError(.unsupportedURL)))
        #expect(!HTTPRetry.isRetriable(ContentDirectoryClient.ClientError.httpError(500)))
    }
}

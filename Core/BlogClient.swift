import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public struct BlogClient: Sendable {
    public let connection: BlogConnection
    private let streamSessionFactory: @Sendable () -> URLSession
    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.urlCache = nil
        config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }
    private static let session = makeSession()

    public init(connection: BlogConnection) {
        self.connection = connection
        streamSessionFactory = { Self.makeSession() }
    }

    init(connection: BlogConnection, streamSessionFactory: @escaping @Sendable () -> URLSession) {
        self.connection = connection
        self.streamSessionFactory = streamSessionFactory
    }

    private func request(_ path: String, body: JSONValue? = nil) throws -> URLRequest {
        var request = URLRequest(url: connection.url(path))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !connection.token.isEmpty { request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func check(_ response: URLResponse, body: Data = Data()) throws {
        guard let http = response as? HTTPURLResponse else { throw AgentError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw HTTPFailure(status: http.statusCode, body: body) }
    }

    public func json(_ path: String, body: JSONValue? = nil) async throws -> JSONValue {
        let (data, response) = try await Self.session.data(for: request(path, body: body))
        try check(response, body: data)
        guard data.count <= 2_097_152 else { throw AgentError.frameTooLarge }
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        if let code = json["code"].int, code != 200 {
            throw AgentError.message(json["message"].string ?? "博客未完成请求。")
        }
        return json
    }

    public func stream(_ body: JSONValue, trace: ChatTrace = ChatTrace()) -> ManagedChatStream {
        ManagedChatStream(trace: trace) { emit in
            // Per-stream ownership makes parse failures and cancellation close this HTTP
            // connection explicitly, without invalidating unrelated overview requests.
            let session = streamSessionFactory()
            defer { session.invalidateAndCancel() }
            var request = try request("/api/chat/stream", body: body)
            request.setValue("2", forHTTPHeaderField: "X-Agent-Stream-Version")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue(trace.requestID, forHTTPHeaderField: "X-Request-ID")
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw AgentError.invalidResponse }
            trace.response(status: http.statusCode, serverRequestID: http.value(forHTTPHeaderField: "X-Request-ID"))
            if !(200..<300).contains(http.statusCode) {
                var data = Data()
                for try await byte in bytes {
                    guard data.count < 65_536 else { throw AgentError.frameTooLarge }
                    data.append(byte)
                }
                throw HTTPFailure(status: http.statusCode, body: data)
            }
            guard response.mimeType == "text/event-stream" else { throw AgentError.protocolViolation }
            var parser = SSEDecoder()
            var byteCount = 0
            for try await byte in bytes {
                try Task.checkCancellation()
                byteCount += 1
                guard byteCount <= 4_194_304 else { throw AgentError.frameTooLarge }
                let ignored = parser.ignoredExtensionCount
                let parsed: AgentEvent?
                do { parsed = try parser.consume(byte: byte) }
                catch { trace.invalidFrame(parser.lastEventName); throw error }
                if let event = parsed {
                    emit(event)
                    if event.name == "error" { throw AgentError.message(event.data.string ?? "Agent 未完成本轮。") }
                    if event.name == "done" {
                        try parser.finish()
                        return // done is authoritative; do not wait for TCP EOF or a timeout.
                    }
                } else if parser.ignoredExtensionCount != ignored { trace.event("extension") }
            }
            try parser.finish()
        }
    }
}

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
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.urlCache = nil
        config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }()

    public init(connection: BlogConnection) { self.connection = connection }

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

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AgentError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw AgentError.message("登录已失效，请重新登录。")
        case 403: throw AgentError.message("当前账号没有这项权限。")
        case 409: throw AgentError.message("状态已变化或操作已被消费，请刷新核对；本次不会自动重试。")
        case 429: throw AgentError.message("请求过于频繁，请稍后再试。")
        default: throw AgentError.message("博客请求失败（\(http.statusCode)）。")
        }
    }

    public func json(_ path: String, body: JSONValue? = nil) async throws -> JSONValue {
        let (data, response) = try await Self.session.data(for: request(path, body: body))
        try check(response)
        guard data.count <= 2_097_152 else { throw AgentError.frameTooLarge }
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        if let code = json["code"].int, code != 200 {
            throw AgentError.message(json["message"].string ?? "博客未完成请求。")
        }
        return json
    }

    public func stream(_ body: JSONValue) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try request("/api/chat/stream", body: body)
                    request.setValue("2", forHTTPHeaderField: "X-Agent-Stream-Version")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, response) = try await Self.session.bytes(for: request)
                    try check(response)
                    guard response.mimeType == "text/event-stream" else { throw AgentError.protocolViolation }
                    var parser = SSEDecoder()
                    var byteCount = 0
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        byteCount += 1
                        guard byteCount <= 4_194_304 else { throw AgentError.frameTooLarge }
                        if let event = try parser.consume(byte: byte) { continuation.yield(event) }
                    }
                    try parser.finish()
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

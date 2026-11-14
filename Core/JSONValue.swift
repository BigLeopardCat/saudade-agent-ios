import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String)
    case number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let b = try? value.decode(Bool.self) { self = .bool(b) }
        else if let n = try? value.decode(Double.self) { self = .number(n) }
        else if let s = try? value.decode(String.self) { self = .string(s) }
        else if let a = try? value.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try value.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let o): try value.encode(o)
        case .array(let a): try value.encode(a)
        case .string(let s): try value.encode(s)
        case .number(let n): try value.encode(n)
        case .bool(let b): try value.encode(b)
        case .null: try value.encodeNil()
        }
    }

    public subscript(_ key: String) -> JSONValue { object?[key] ?? .null }
    public var object: [String: JSONValue]? { if case .object(let x) = self { return x }; return nil }
    public var array: [JSONValue]? { if case .array(let x) = self { return x }; return nil }
    public var string: String? { if case .string(let x) = self { return x }; return nil }
    public var number: Double? { if case .number(let x) = self { return x }; return nil }
    public var bool: Bool? { if case .bool(let x) = self { return x }; return nil }
    public var int: Int? {
        guard let n = number, n.isFinite, n.rounded() == n, n >= -9_007_199_254_740_991,
              n <= 9_007_199_254_740_991 else { return nil }
        return Int(n)
    }
}

public enum AgentError: LocalizedError, Equatable {
    case invalidURL, invalidResponse, protocolViolation, incompleteStream, frameTooLarge
    case message(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "请输入不含路径、账号或参数的 HTTPS 博客地址。"
        case .invalidResponse: return "博客返回了无法识别的数据。"
        case .protocolViolation: return "聊天协议不匹配，已停止处理本轮。"
        case .incompleteStream: return "连接中断，回复可能不完整；请核对任务状态后再操作。"
        case .frameTooLarge: return "聊天事件超过大小限制。"
        case .message(let text): return text
        }
    }
}

public struct BlogConnection: Sendable {
    public let origin: URL
    public let token: String

    public init(origin: String, token: String) throws {
        guard let url = URL(string: origin.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { throw AgentError.invalidURL }
        self.origin = url
        self.token = token
    }

    public func url(_ path: String) -> URL { URL(string: path, relativeTo: origin)!.absoluteURL }
}

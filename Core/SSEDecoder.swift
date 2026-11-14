import Foundation

public struct AgentEvent: Sendable {
    public let name: String
    public let data: JSONValue
}

/// Bounded SSE framing. No automatic reconnect or request replay.
public struct SSEDecoder {
    private var name = ""
    private var lines: [String] = []
    private var size = 0
    private var firstLine = true
    private var lineBytes: [UInt8] = []
    private var previousCR = false
    public private(set) var terminal = false
    public private(set) var failed = false

    public init() {}

    public mutating func consume(byte: UInt8) throws -> AgentEvent? {
        if previousCR {
            previousCR = false
            if byte == 10 { return nil }
        }
        if byte == 10 || byte == 13 {
            previousCR = byte == 13
            guard let line = String(bytes: lineBytes, encoding: .utf8) else { throw AgentError.protocolViolation }
            lineBytes.removeAll(keepingCapacity: true)
            return try consume(line: line)
        }
        guard lineBytes.count < 1_048_576 else { throw AgentError.frameTooLarge }
        lineBytes.append(byte)
        return nil
    }

    public mutating func consume(line raw: String) throws -> AgentEvent? {
        var line = raw
        if firstLine { firstLine = false; if line.hasPrefix("\u{FEFF}") { line.removeFirst() } }
        if line.isEmpty {
            defer { name = ""; lines = []; size = 0 }
            guard !lines.isEmpty else { return nil }
            guard !terminal else { throw AgentError.protocolViolation }
            let data = Data(lines.joined(separator: "\n").utf8)
            let value = try JSONDecoder().decode(JSONValue.self, from: data)
            switch name {
            case "text", "error": guard value.string != nil else { throw AgentError.protocolViolation }
            case "progress":
                guard value.string != nil || value["text"].string != nil else { throw AgentError.protocolViolation }
            case "done", "text_reset":
                guard value.object?.isEmpty == true else { throw AgentError.protocolViolation }
            case "confirmation":
                guard let card = try? Confirmation(value), !card.id.isEmpty else { throw AgentError.protocolViolation }
            case "command":
                guard ["navigate", "effect", "darkmode", "appearance", "article_editor"].contains(value["kind"].string ?? "")
                else { throw AgentError.protocolViolation }
            case "task_input": guard value["task_id"].string != nil else { throw AgentError.protocolViolation }
            default: throw AgentError.protocolViolation
            }
            if name == "done" || name == "error" { terminal = true; failed = name == "error" }
            return AgentEvent(name: name, data: value)
        }
        size += line.utf8.count
        guard size <= 1_048_576 else { throw AgentError.frameTooLarge }
        if line.hasPrefix(":") { return nil }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts[0])
        var value = parts.count == 2 ? String(parts[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        switch field {
        case "event": name = value
        case "data": lines.append(value)
        default: break
        }
        return nil
    }

    public func finish() throws {
        guard terminal, lines.isEmpty, lineBytes.isEmpty else { throw AgentError.incompleteStream }
    }
}

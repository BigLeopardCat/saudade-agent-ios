import Foundation

public struct AgentEvent: Sendable {
    public let name: String
    public let data: JSONValue
    public init(name: String, data: JSONValue) { self.name = name; self.data = data }
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
    public private(set) var lastEventName: String?
    public private(set) var ignoredExtensionCount = 0

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
            let known = ["text", "error", "progress", "done", "text_reset", "confirmation", "command", "task_input", "pending", "receipts"]
            lastEventName = known.contains(name) ? name : "extension"
            // Extensions have no authority over text, completion, confirmation or client actions.
            // Do not even decode their opaque payload; keep the framing and byte limits.
            if !known.contains(name) {
                guard name.utf8.count <= 128, name.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) else {
                    throw AgentError.protocolViolation
                }
                ignoredExtensionCount += 1
                return nil
            }
            let data = Data(lines.joined(separator: "\n").utf8)
            let value = try JSONDecoder().decode(JSONValue.self, from: data)
            switch name {
            case "text", "error": guard value.string != nil else { throw AgentError.protocolViolation }
            case "progress":
                guard value.string != nil || Self.validProgress(value) else { throw AgentError.protocolViolation }
            case "done", "text_reset":
                guard value.object?.isEmpty == true else { throw AgentError.protocolViolation }
            case "confirmation":
                guard let card = try? Confirmation(value), !card.id.isEmpty else { throw AgentError.protocolViolation }
            case "command":
                guard ["navigate", "effect", "darkmode", "appearance", "article_editor"].contains(value["kind"].string ?? "")
                else { throw AgentError.protocolViolation }
            case "task_input":
                guard let task = value["task_id"].string, !task.isEmpty, task.utf8.count <= 100,
                      value["ready"].bool != nil || value["input"].object != nil || value["inputs"].array != nil
                else { throw AgentError.protocolViolation }
            case "pending":
                guard value.object != nil else { throw AgentError.protocolViolation }
            case "receipts":
                guard let rows = value.array, rows.allSatisfy({ $0.object != nil }) else { throw AgentError.protocolViolation }
            default: throw AgentError.protocolViolation
            }
            if name == "done" || name == "error" { terminal = true; failed = name == "error" }
            // These are host-internal persistence controls, never client authorization.
            return AgentEvent(name: name, data: ["pending", "receipts"].contains(name) ? .null : value)
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

    private static func validProgress(_ value: JSONValue) -> Bool {
        guard let text = value["text"].string, !text.isEmpty, text.unicodeScalars.count <= 300,
              let id = value["work"]["id"].string, !id.isEmpty, id.unicodeScalars.count <= 128,
              let stage = value["work"]["stage"].string, !stage.isEmpty, stage.unicodeScalars.count <= 64,
              let status = value["work"]["status"].string else { return false }
        return ["running", "waiting", "completed", "failed", "cancelled", "unknown"].contains(status)
    }
}

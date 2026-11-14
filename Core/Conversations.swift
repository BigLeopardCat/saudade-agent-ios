import Foundation

public struct Conversation: Identifiable, Equatable, Sendable {
    public let id: Int
    public var title: String?
    public let createdAt: Date?
    public var updatedAt: Date?
    public var pinned: Bool
    public var displayTitle: String { title.flatMap { $0.isEmpty ? nil : $0 } ?? "新对话" }

    public init(id: Int, title: String?, createdAt: Date?, updatedAt: Date?, pinned: Bool = false) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.updatedAt = updatedAt; self.pinned = pinned
    }
    public static func list(_ value: JSONValue) throws -> [Conversation] {
        guard let rows = value["conversations"].array, rows.count <= 200 else { throw AgentError.invalidResponse }
        let result = try rows.map { row -> Conversation in
            guard let id = row["id"].int, id > 0, id <= Int(Int32.max),
                  row["title"] == .null || row["title"].string != nil,
                  let pinned = row["pinned"].bool else { throw AgentError.invalidResponse }
            return Conversation(id: id, title: row["title"].string,
                createdAt: ChatTime.date(milliseconds: row["created_at"].number),
                updatedAt: ChatTime.date(milliseconds: row["updated_at"].number), pinned: pinned)
        }
        guard Set(result.map(\.id)).count == result.count else { throw AgentError.invalidResponse }
        return result // Keep the server's pinned/activity ordering.
    }
}

public struct ChatMessage: Identifiable, Equatable, Sendable, Decodable {
    public let id: String
    public let databaseID: Int?
    public let user: Bool
    public let time: Date?
    public var text: String
    public var incomplete = false
    public var truncated = false
    public let imageCount: Int

    public init(user: Bool, text: String, time: Date? = Date()) {
        id = "local:" + UUID().uuidString; databaseID = nil; self.user = user
        self.text = text; self.time = time; imageCount = 0
    }
    enum CodingKeys: String, CodingKey { case id, role, content, time, images }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let key = try c.decode(Int.self, forKey: .id)
        let role = try c.decode(String.self, forKey: .role)
        guard key > 0, key <= Int(Int32.max), ["user", "assistant"].contains(role) else { throw AgentError.invalidResponse }
        id = "db:\(key)"; databaseID = key; user = role == "user"
        let body = try c.decode(String.self, forKey: .content)
        if body.utf8.count > 131_072 {
            // Bound off-screen Markdown work. Never apply this to confirmation review content.
            text = String(decoding: body.utf8.prefix(131_068), as: UTF8.self); truncated = true
        } else { text = body }
        time = ChatTime.date(milliseconds: try c.decodeIfPresent(Double.self, forKey: .time))
        // Do not decode or retain the potentially large base64 image strings.
        imageCount = c.contains(.images) ? (try c.nestedUnkeyedContainer(forKey: .images).count ?? 0) : 0
    }
}

public struct ChatHistoryPage: Decodable, Sendable {
    public let items: [ChatMessage]
    public let count: Int
    public let conversationID: Int
    enum CodingKeys: String, CodingKey { case items, count; case conversationID = "conversation_id" }
    public func validate(conversationID expected: Int, beforeID: Int? = nil) throws {
        let ids = items.compactMap(\.databaseID)
        guard conversationID == expected, count == items.count, count <= 50,
              ids.count == count, Set(ids).count == count, ids == ids.sorted(),
              beforeID == nil || ids.allSatisfy({ $0 < beforeID! }) else { throw AgentError.invalidResponse }
    }
    public var oldestID: Int? { items.first?.databaseID }
    public var mayHaveOlder: Bool { count == 50 }
}

/// Only the active conversation is rendered. Older pages remain browsable beyond this memory window.
public struct HistoryWindow: Sendable {
    public static let maximumMessages = 200
    public static let maximumBytes = 8_388_608
    public let conversationID: Int
    public private(set) var items: [ChatMessage]
    public private(set) var oldestID: Int?
    public private(set) var mayHaveOlder: Bool
    public private(set) var droppedNewer = false
    public init(page: ChatHistoryPage) throws {
        try page.validate(conversationID: page.conversationID)
        conversationID = page.conversationID; items = page.items
        oldestID = page.oldestID; mayHaveOlder = page.mayHaveOlder
    }
    public mutating func prepend(_ page: ChatHistoryPage) throws {
        try page.validate(conversationID: conversationID, beforeID: oldestID)
        guard mayHaveOlder else { throw AgentError.invalidResponse }
        items = page.items + items
        oldestID = page.oldestID ?? oldestID; mayHaveOlder = page.mayHaveOlder
        var bytes = items.reduce(0) { $0 + $1.text.utf8.count }
        while items.count > Self.maximumMessages || (bytes > Self.maximumBytes && items.count > page.items.count) {
            bytes -= items.removeLast().text.utf8.count; droppedNewer = true
        }
    }
}

public struct CurrentConfirmation: Sendable {
    public let card: Confirmation?
    public init(_ value: JSONValue, taskID expected: String? = nil) throws {
        guard value.object?["confirmation"] != nil else { throw AgentError.invalidResponse }
        if let expected, value["task_id"].string != expected { throw AgentError.protocolViolation }
        if value["confirmation"] == .null { card = nil; return }
        let card = try Confirmation(value["confirmation"])
        guard value["task_id"].string == card.taskID else { throw AgentError.protocolViolation }
        self.card = card
    }
}

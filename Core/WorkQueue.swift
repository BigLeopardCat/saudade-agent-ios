import Foundation

/// Human business work, independent of paused agent executions.
public struct WorkQueue: Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case comments, board, quota
        public var title: String {
            switch self { case .comments: return "评论审核"; case .board: return "留言审核"; case .quota: return "额度申请" }
        }
    }
    public struct Item: Identifiable, Sendable {
        public let kind: Kind
        public let number: Int
        public let author: String
        public let preview: String
        public var id: String { "\(kind.rawValue)-\(number)" }
        public var reviewPrompt: String {
            "请只读取\(kind.title) #\(number) 的当前完整内容和状态，供我人工审阅。先不要执行批准、驳回或任何写入，等待我明确决定。"
        }
    }
    public let counts: [Kind: Int]
    public let items: [Item]
    public let issues: [String]
    public var total: Int? { counts.count == Kind.allCases.count ? counts.values.reduce(0, +) : nil }
    public var knownTotal: Int {
        Kind.allCases.reduce(0) { total, kind in total + max(counts[kind] ?? 0, items.filter { $0.kind == kind }.count) }
    }
    public static let unavailable = WorkQueue(counts: [:], items: [], issues: ["人工待办尚未读取"])
    public static let demo = WorkQueue(counts: [.comments: 1, .board: 1, .quota: 0], items: [
        .init(kind: .comments, number: 101, author: "演示读者", preview: "文章很有帮助，期待下一篇。"),
        .init(kind: .board, number: 201, author: "演示访客", preview: "泠月喵，晚上好！")
    ], issues: [])

    public static func project(summary: JSONValue?, comments: JSONValue?, board: JSONValue?, quota: JSONValue?) -> WorkQueue {
        var counts: [Kind: Int] = [:]
        for kind in [Kind.comments, .board] {
            if let count = summary?["data"][kind.rawValue]["pending"].int, count >= 0 { counts[kind] = count }
        }
        if let count = quota?["total"].int, count >= 0 { counts[.quota] = count }
        var items: [Item] = []
        var issues: [String] = []
        for (kind, response) in [(Kind.comments, comments), (.board, board), (.quota, quota)] {
            guard let rows = response?["data"].array else { issues.append("\(kind.title)列表暂不可用"); continue }
            for row in rows {
                guard let number = row[kind == .board ? "talkKey" : "id"].int, number > 0,
                      row[kind == .quota ? "status" : "approved"].int == 0,
                      row["isDeleted"].bool != true, row["isDeleted"].int != 1 else { continue }
                let author = row["nickname"].string.flatMap { $0.isEmpty ? nil : $0 } ?? row["username"].string ?? "访客"
                items.append(.init(kind: kind, number: number, author: String(author.prefix(100)),
                                   preview: String((row[kind == .quota ? "reason" : "content"].string ?? "未填写说明").prefix(240))))
            }
        }
        for kind in Kind.allCases {
            if counts[kind] == nil { issues.append("\(kind.title)数量未知，不能视为零") }
            else { counts[kind] = max(counts[kind]!, items.filter { $0.kind == kind }.count) }
        }
        return WorkQueue(counts: counts, items: items, issues: issues)
    }

    public static func load(client: BlogClient) async -> WorkQueue {
        async let summary = fetch(client, "/api/protected/moderation/summary")
        async let comments = fetch(client, "/api/protect/comments?status=pending&deleted=false&page=1&page_size=10")
        async let board = fetch(client, "/api/protect/board?status=pending&page=1&page_size=10")
        async let quota = fetch(client, "/api/protected/quota/requests?status=pending&page=1&page_size=10")
        return await project(summary: summary, comments: comments, board: board, quota: quota)
    }
    private static func fetch(_ client: BlogClient, _ path: String) async -> JSONValue? { try? await client.json(path) }
}

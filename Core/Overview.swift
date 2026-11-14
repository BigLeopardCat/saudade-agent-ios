import Foundation

public struct Overview: Sendable {
    public struct Metric: Identifiable, Sendable {
        public let id: String
        public let value: String
    }
    public struct Item: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let subtitle: String
    }
    public let observedAt: Date
    public let healthy: Bool?
    public let summary: String
    public let metrics: [Metric]
    public let articles: [Item]
    public let tasks: [JSONValue]
    public let issues: [String]
    public let tasksAvailable: Bool

    public static var demo: Overview { Overview(
        observedAt: Date(), healthy: true, summary: "演示博客运行平稳，喵。",
        metrics: [.init(id: "CPU", value: "12%"), .init(id: "内存", value: "48%"), .init(id: "服务", value: "3/3")],
        articles: [.init(id: "1", title: "给博客加一点月光", subtitle: "演示文章 · 不是线上动态"),
                   .init(id: "2", title: "把泠月喵带在身边", subtitle: "演示文章 · 不是线上动态")],
        tasks: [], issues: [], tasksAvailable: true) }

    public static func load(client: BlogClient) async -> Overview {
        async let diagnostic = result { try await client.json("/api/protected/diagnostics") }
        async let articles = result { try await client.json("/api/public/articles?page=1&page_size=5") }
        async let tasks = result { try await client.json("/api/chat/tasks") }
        let (d, a, t) = await (diagnostic, articles, tasks)
        var issues: [String] = []
        var healthy: Bool?
        var metrics: [Metric] = []
        var observedAt = Date()
        if case .success(let value) = d {
            let data = value["data"]
            if data["schemaVersion"].int == 1, let services = data["services"].array, !services.isEmpty {
                healthy = services.allSatisfy { ["running", "ready"].contains($0["state"].string ?? "") }
                let h = data["host"]
                let cpu = h["cpuPercent"].number.map { String(format: "%.0f%%", $0) } ?? "采样中"
                let total = h["memory"]["totalBytes"].number ?? 0
                let available = h["memory"]["availableBytes"].number
                let memory = total > 0 && available != nil
                    ? String(format: "%.0f%%", (1 - available! / total) * 100) : "未知"
                metrics = [.init(id: "CPU", value: cpu), .init(id: "内存", value: memory),
                           .init(id: "服务", value: "\(services.filter { ["running", "ready"].contains($0["state"].string ?? "") }.count)/\(services.count)")]
                if let raw = data["observedAt"].string, let date = parseDate(raw) { observedAt = date }
            } else { issues.append("服务器诊断：返回格式不兼容") }
        } else if case .failure(let error) = d { issues.append("服务器诊断：\(error.localizedDescription)") }
        var items: [Item] = []
        if case .success(let value) = a, let list = value["data"].array {
            items = list.compactMap { row in
                guard let id = row["id"].int, let title = row["title"].string else { return nil }
                return Item(id: String(id), title: title, subtitle: "公开文章 #\(id)")
            }
        } else { issues.append("近期文章暂时无法读取") }
        var paused: [JSONValue] = []
        var tasksAvailable = false
        if case .success(let value) = t, let list = value["paused"]["items"].array,
           value["paused"]["unavailable"].bool != true {
            paused = list; tasksAvailable = true
        } else { issues.append("暂停任务暂时无法读取；不能视为没有待办") }
        return Overview(observedAt: observedAt, healthy: healthy,
                        summary: healthy == true ? "博客运行平稳，喵。" : (healthy == false ? "有服务需要你留意。" : "服务器状态暂时未知。"),
                        metrics: metrics, articles: items, tasks: paused, issues: issues, tasksAvailable: tasksAvailable)
    }

    private static func result<T>(_ action: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await action()) } catch { return .failure(error) }
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

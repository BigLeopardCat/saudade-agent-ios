import ActivityKit
import Foundation
import LingyueCore
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    struct Message: Identifiable {
        let id: UUID
        let user: Bool
        var text: String
        var incomplete = false
        init(user: Bool, text: String) { id = UUID(); self.user = user; self.text = text }
    }
    @Published var configuration = ConnectionStore.load()
    @Published var overview: Overview?
    @Published var messages: [Message] = []
    @Published var confirmation: Confirmation?
    @Published var selectedTab = 0
    @Published var busy = false
    @Published var refreshing = false
    @Published var progress = ""
    @Published var error: String?
    @Published var islandActive = !Activity<CompanionAttributes>.activities.isEmpty
    @Published var currentConversation: Int?
    private var generation = UUID()
    private var streamTask: Task<Void, Never>?

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        let current = generation
        defer { refreshing = false }
        do {
            let result = try await ConnectionStore.overview()
            guard generation == current else { return }
            overview = result
            await CompanionActivity.update(.init(overview: result, demo: configuration.demo))
        } catch { if generation == current { self.error = error.localizedDescription } }
        islandActive = !Activity<CompanionAttributes>.activities.isEmpty
    }

    func startIsland() async {
        guard !busy else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            error = "请在系统设置里允许泠月喵使用实时活动。"; return
        }
        if overview == nil { await refresh() }
        guard let overview else { return }
        do {
            let state = CompanionAttributes.ContentState(overview: overview, demo: configuration.demo)
            if Activity<CompanionAttributes>.activities.isEmpty {
                _ = try Activity.request(attributes: CompanionAttributes(name: "泠月喵"),
                    content: ActivityContent(state: state, staleDate: state.updatedAt.addingTimeInterval(300)), pushType: nil)
            } else { await CompanionActivity.update(state) }
            islandActive = true
        } catch { self.error = error.localizedDescription }
    }

    func endIsland() async { await CompanionActivity.end(); islandActive = false }

    func connect(origin: String, username: String, password: String) async {
        guard !busy, !refreshing else { return }
        busy = true; defer { busy = false }
        do {
            let connection = try BlogConnection(origin: origin, token: "")
            let canonical = connection.origin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let response = try await BlogClient(connection: connection).json("/api/login", body: .object([
                "username": .string(username), "password": .string(password)
            ]))
            guard let token = response["data"].string, !token.isEmpty else { throw AgentError.invalidResponse }
            // Verify the issued login before committing the connection locally.
            let authenticated = BlogClient(connection: try BlogConnection(origin: canonical, token: token))
            _ = try await authenticated.json("/api/protected/profile")
            try ConnectionStore.setToken(token, origin: canonical)
            await changeConfiguration(.init(demo: false, origin: canonical))
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func useDemo() async {
        guard !busy, !refreshing else { return }
        await changeConfiguration(.init())
        await refresh()
    }

    func logout() async {
        guard !busy, !refreshing else { return }
        do {
            try ConnectionStore.setToken("", origin: configuration.origin)
            await changeConfiguration(.init())
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    private func changeConfiguration(_ value: ConnectionStore.Configuration) async {
        generation = UUID()
        await endIsland()
        confirmation = nil; currentConversation = nil; messages = []; overview = nil; error = nil
        configuration = value
        do { try ConnectionStore.save(value) } catch { self.error = error.localizedDescription }
    }

    func newChat() {
        guard !busy else { return }
        confirmation = nil; currentConversation = nil; messages = []; progress = ""
    }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty else { return }
        guard text.unicodeScalars.count <= 4000 else { error = "每条消息最多 4000 字。"; return }
        messages.append(Message(user: true, text: text))
        confirmation = nil
        startStream(message: text)
    }

    func approve(_ card: Confirmation) {
        guard !busy, confirmation?.id == card.id, card.supportsNativeReview, !card.expired else { return }
        confirmation = nil
        startStream(message: "", approving: card)
    }

    func cancelConfirmation(_ card: Confirmation) async {
        guard !busy, confirmation?.id == card.id, let conversation = currentConversation else { return }
        busy = true; defer { busy = false }
        do {
            if !configuration.demo {
                let response = try await ConnectionStore.client(configuration).json("/api/chat/confirmation/cancel", body: .object([
                    "conversation_id": .number(Double(conversation)), "token": .string(card.token)
                ]))
                guard response["cancelled"].bool == true else { throw AgentError.message("未能确认撤销结果，请重新核对。") }
            }
            confirmation = nil
            messages.append(Message(user: false, text: "已撤销这张确认卡，未执行改动。"))
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func openTask(_ task: JSONValue) async {
        guard !busy, let cid = task["conversation_id"].int, let id = task["task_id"].string else { return }
        busy = true; defer { busy = false }
        do {
            let client = try ConnectionStore.client(configuration)
            let history = try await client.json("/api/chat/history?conversation_id=\(cid)")
            let card = try await client.json("/api/chat/task/confirmation", body: .object([
                "conversation_id": .number(Double(cid)), "task_id": .string(id)
            ]))
            guard let items = history["items"].array else { throw AgentError.invalidResponse }
            currentConversation = cid
            messages = items.compactMap {
                guard let text = $0["content"].string, let role = $0["role"].string else { return nil }
                return Message(user: role == "user", text: text)
            }
            confirmation = card["confirmation"] == .null ? nil : try Confirmation(card["confirmation"])
            selectedTab = 1
        } catch { self.error = error.localizedDescription }
    }

    func cancelTask(_ task: JSONValue) async {
        guard !busy, let cid = task["conversation_id"].int, let id = task["task_id"].string else { return }
        busy = true; defer { busy = false }
        do {
            let response = try await ConnectionStore.client(configuration).json("/api/chat/tasks/cancel", body: .object([
                "conversation_id": .number(Double(cid)), "task_id": .string(id)
            ]))
            guard response["cancelled"].bool == true else { throw AgentError.message("未能确认任务取消结果。") }
            if currentConversation == cid { confirmation = nil }
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    private func startStream(message: String, approving: Confirmation? = nil) {
        busy = true; error = nil; progress = "泠月喵正在想…"
        let index = messages.count
        messages.append(Message(user: false, text: ""))
        streamTask = Task {
            var completed = false
            defer { busy = false; progress = ""; streamTask = nil }
            do {
                if configuration.demo {
                    try await demoReply(message: message, approving: approving, index: index)
                    completed = true
                } else {
                    let client = try ConnectionStore.client(configuration)
                    if currentConversation == nil {
                        let response = try await client.json("/api/chat/conversations", body: .object([:]))
                        guard let id = response["id"].int, id > 0 else { throw AgentError.invalidResponse }
                        currentConversation = id
                    }
                    let turn = UUID().uuidString
                    var body: [String: JSONValue] = [
                        "message": .string(message), "conversation_id": .number(Double(currentConversation!)),
                        "turn_id": .string(turn), "browser_feedback": .bool(false), "task_inputs": .bool(false)
                    ]
                    if let approving {
                        body["confirm_token"] = .string(approving.token)
                        body["confirm_pick"] = .string("")
                    } else { body["task_id"] = .string(turn) }
                    for try await event in client.stream(.object(body)) {
                        try Task.checkCancellation()
                        switch event.name {
                        case "text": messages[index].text += event.data.string ?? ""
                        case "text_reset": messages[index].text = ""
                        case "progress": progress = event.data.string ?? event.data["text"].string ?? "处理中…"
                        case "confirmation": confirmation = try Confirmation(event.data)
                        case "command":
                            // Native clients cannot report browser/editor state or execute page commands.
                            progress = "这一步需要在博客页面继续。"
                        case "error": throw AgentError.message(event.data.string ?? "Agent 未完成本轮。")
                        case "done": completed = true
                        default: break
                        }
                    }
                }
                guard completed else { throw AgentError.incompleteStream }
                if messages[index].text.isEmpty { messages[index].text = confirmation == nil ? "本轮已结束。" : "有一项操作需要你审阅。" }
                await refresh()
            } catch {
                messages[index].incomplete = true
                if messages[index].text.isEmpty { messages[index].text = "本轮未完整结束。" }
                confirmation = nil
                self.error = error is CancellationError ? "已停止接收；远端可能仍在处理，请核对事务状态。" : error.localizedDescription
            }
        }
    }

    func stopReceiving() { streamTask?.cancel() }

    private func demoReply(message: String, approving: Confirmation?, index: Int) async throws {
        currentConversation = -1
        let reply: String
        if approving != nil {
            reply = "演示确认已收到，喵。没有修改真实博客数据。"
        } else if message.contains("审核") || message.contains("事务") {
            let now = Date().timeIntervalSince1970
            confirmation = try Confirmation(.object([
                "id": .string(UUID().uuidString), "task_id": .string("demo-task"),
                "q": .string("通过这条演示留言吗？"), "token": .string("demo-only"),
                "exp": .number(now + 300), "server_time": .number(now),
                "opts": .array([.object(["label": .string("确认通过"), "value": .string("yes")]),
                                .object(["label": .string("撤销"), "value": .string("no")])]),
                "details": .object(["fields": .array([.object(["label": .string("留言内容"), "value": .string("泠月喵，晚上好！")])]), "sections": .array([])]),
                "notices": .array([.object(["kind": .string("info"), "text": .string("这是一张演示卡，不会提交真实操作。")])])
            ]))
            reply = "我准备了一张演示确认卡。先看看内容，再决定要不要执行，喵。"
        } else if message.contains("服务器") || message.contains("状态") {
            reply = "演示服务器 CPU 12%，内存 48%，三个服务正常。连接你的博客后，这里会使用真实诊断数据。"
        } else if message.contains("动态") || message.contains("最近") {
            reply = "演示里有两篇文章：《给博客加一点月光》和《把泠月喵带在身边》。真实近期内容会从博客读取。"
        } else {
            reply = "在呢，喵。今天想聊什么？我现在是本地演示模式，接入你的博客后，就能延续真正的泠月喵人设和 Agent 能力。"
        }
        for character in reply {
            try await Task.sleep(for: .milliseconds(18))
            messages[index].text.append(character)
        }
    }
}

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
    @Published private(set) var confirmationState = ConfirmationReviewState()
    var confirmation: Confirmation? { confirmationState.card }
    @Published var selectedTab = 0
    @Published var busy = false
    @Published private(set) var receiving = false
    @Published var refreshing = false
    @Published var progress = ""
    @Published var error: String?
    @Published var islandActive = !Activity<CompanionAttributes>.activities.isEmpty
    @Published var currentConversation: Int?
    @Published private(set) var profile: UserProfile?
    @Published private(set) var identityNotice: String?
    @Published private(set) var hasSession = false
    @Published var loginPresented = false
    private var generation = UUID()
    private var streamTask: Task<Void, Never>?
    private var activeStream: ManagedChatStream?
    private var activeTrace: ChatTrace?
    private var currentScene = "unknown"
    private var chatVisible = false
    private var stopMarker = UserDefaults.standard.string(forKey: "lingyue.stopMarker")
    private var pendingText = ""
    private var streamingIndex: Int?
    private var lastTextPublish: TimeInterval = 0

    init() { hasSession = !configuration.demo && !ConnectionStore.token(for: configuration.origin).isEmpty }

    func observeScene(_ scene: ScenePhase) {
        switch scene {
        case .active: currentScene = "active"
        case .inactive: currentScene = "inactive"
        case .background: currentScene = "background"
        @unknown default: currentScene = "unknown"
        }
        // Observation only. Suspension or network loss is diagnosed separately, not labelled user-stop.
        activeTrace?.lifecycle(scene: currentScene, chatVisible: chatVisible)
        if scene == .active {
            flushText()
            let marker = UserDefaults.standard.string(forKey: "lingyue.stopMarker")
            if marker != stopMarker { stopMarker = marker; stopReceiving() }
            islandActive = !Activity<CompanionAttributes>.activities.isEmpty
        }
    }

    func observeChatVisibility(_ visible: Bool) {
        chatVisible = visible
        activeTrace?.lifecycle(scene: currentScene, chatVisible: visible)
        if visible { flushText() }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        let current = generation
        defer { refreshing = false }
        do {
            if !configuration.demo {
                do {
                    let value = try await ConnectionStore.client(configuration).json("/api/protected/profile")
                    guard generation == current else { return }
                    profile = try UserProfile(value); identityNotice = nil
                } catch {
                    guard generation == current else { return }
                    identityNotice = "登录状态暂未核对成功，请检查网络或重新登录。"
                    if let http = error as? HTTPFailure, [401, 403].contains(http.status) { profile = nil }
                }
            }
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

    func endIsland() async {
        stopReceiving()
        await CompanionActivity.end(); islandActive = false
    }

    func companionEnded() {
        stopMarker = UserDefaults.standard.string(forKey: "lingyue.stopMarker")
        stopReceiving(); islandActive = false
    }

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
            let identity = try UserProfile(await authenticated.json("/api/protected/profile"))
            try ConnectionStore.setToken(token, origin: canonical)
            await changeConfiguration(.init(demo: false, origin: canonical))
            profile = identity
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
        confirmationState.clear(); currentConversation = nil; messages = []; overview = nil; error = nil
        profile = nil; identityNotice = nil
        configuration = value
        hasSession = !value.demo && !ConnectionStore.token(for: value.origin).isEmpty
        do { try ConnectionStore.save(value) } catch { self.error = error.localizedDescription }
    }

    func newChat() {
        guard !busy else { return }
        confirmationState.clear(); currentConversation = nil; messages = []; progress = ""
    }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty else { return }
        guard text.unicodeScalars.count <= 4000 else { error = "每条消息最多 4000 字。"; return }
        messages.append(Message(user: true, text: text))
        confirmationState.clear()
        startStream(message: text)
    }

    func approve(_ card: Confirmation) {
        guard !busy, confirmationState.canApprove(card) else { return }
        confirmationState.beginApproval()
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
            confirmationState.clear()
            messages.append(Message(user: false, text: "已撤销这张确认卡，未执行改动。"))
            await refresh()
        } catch { confirmationState.interrupt(); self.error = error.localizedDescription }
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
            trimTranscript()
            confirmationState.clear()
            if card["confirmation"] != .null {
                let restored = try Confirmation(card["confirmation"])
                guard restored.taskID == id && card["task_id"].string == id else { throw AgentError.protocolViolation }
                confirmationState.receive(restored)
            }
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
            if currentConversation == cid { confirmationState.clear() }
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    private func startStream(message: String, approving: Confirmation? = nil) {
        busy = true; receiving = true; error = nil; progress = "泠月喵正在想…"
        let trace = ChatTrace(buildCommit: BuildInfo.commit, sink: { ChatLogStore.shared.append($0) })
        activeTrace = trace
        trace.startedRequest(conversationID: currentConversation, taskID: approving?.taskID)
        trace.lifecycle(scene: currentScene, chatVisible: chatVisible)
        let index = messages.count
        messages.append(Message(user: false, text: ""))
        streamingIndex = index; pendingText = ""; lastTextPublish = 0
        streamTask = Task {
            var completed = false
            defer {
                flushText()
                streamingIndex = nil; pendingText = ""
                trimTranscript()
                activeStream?.cancel(.consumerEnded)
                activeStream = nil; activeTrace = nil
                busy = false; receiving = false; progress = ""; streamTask = nil
            }
            do {
                if configuration.demo {
                    try await demoReply(message: message, approving: approving, index: index)
                    completed = true
                    trace.event("done"); trace.finish()
                } else {
                    let client = try ConnectionStore.client(configuration)
                    if currentConversation == nil {
                        let response = try await client.json("/api/chat/conversations", body: .object([:]))
                        guard let id = response["id"].int, id > 0 else { throw AgentError.invalidResponse }
                        currentConversation = id
                    }
                    let turn = UUID().uuidString
                    let body = approving.map { ChatPayload.approval($0, conversationID: currentConversation!) }
                        ?? ChatPayload.message(message, conversationID: currentConversation!, turnID: turn)
                    trace.startedRequest(conversationID: currentConversation, taskID: approving?.taskID ?? turn)
                    let stream = client.stream(body, trace: trace)
                    activeStream = stream
                    try await withTaskCancellationHandler {
                        for try await event in stream.events {
                            try Task.checkCancellation()
                            switch event.name {
                            case "text": try appendText(event.data.string ?? "")
                            case "text_reset": pendingText = ""; flushText()
                            case "progress": progress = event.data.string ?? event.data["text"].string ?? "处理中…"
                            case "confirmation": confirmationState.receive(try Confirmation(event.data))
                            case "command": progress = "这一步需要在博客页面继续。"
                            case "error": throw AgentError.message(event.data.string ?? "Agent 未完成本轮。")
                            case "done": completed = true
                            default: break
                            }
                        }
                    } onCancel: {
                        stream.cancel(.parentTask)
                    }
                }
                guard completed else { throw AgentError.incompleteStream }
                flushText()
                streamingIndex = nil
                if let approving { confirmationState.finishApproval(approving) }
                if messages[index].text.isEmpty { messages[index].text = confirmation == nil ? "本轮已结束。" : "有一项操作需要你审阅。" }
                receiving = false
                await refresh()
            } catch {
                flushText()
                streamingIndex = nil
                messages[index].incomplete = true
                if messages[index].text.isEmpty { messages[index].text = "本轮未完整结束。" }
                confirmationState.interrupt()
                activeStream?.cancel(.consumerEnded)
                trace.finish(error: error)
                let ns = error as NSError
                let cancelled = error is CancellationError || (ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled)
                let detail = cancelled ? "接收已取消；远端可能仍在处理，请核对事务状态。" : error.localizedDescription
                self.error = "\(detail)\n请求编号：\(trace.requestID)"
            }
        }
    }

    private func appendText(_ text: String) throws {
        guard pendingText.utf8.count + text.utf8.count <= 131_072 else { throw AgentError.frameTooLarge }
        pendingText += text
        let now = ProcessInfo.processInfo.systemUptime
        let interval: TimeInterval = pendingText.utf8.count > 32_768 ? 0.5 : 0.1
        if currentScene == "active", chatVisible, now - lastTextPublish >= interval { flushText() }
    }

    private func flushText() {
        guard let index = streamingIndex, messages.indices.contains(index) else { return }
        if messages[index].text != pendingText { messages[index].text = pendingText }
        lastTextPublish = ProcessInfo.processInfo.systemUptime
    }

    private func trimTranscript() {
        if messages.count > 80 { messages.removeFirst(messages.count - 80) }
        var bytes = messages.reduce(0) { $0 + $1.text.utf8.count }
        while messages.count > 1, bytes > 524_288 { bytes -= messages.removeFirst().text.utf8.count }
        if messages.count == 1, messages[0].text.utf8.count > 524_288 {
            let tail = String(decoding: messages[0].text.utf8.suffix(520_000), as: UTF8.self)
            messages[0].text = "【本机仅显示这条长历史消息的末尾，完整内容请到博客查看。】\n\n" + tail
        }
    }

    func stopReceiving() {
        guard receiving else { return }
        activeTrace?.cancel(.userStop)
        activeStream?.cancel(.userStop)
        streamTask?.cancel()
    }

    func reloadConfirmation() async {
        guard !busy, let previous = confirmation, let cid = currentConversation else { return }
        busy = true; defer { busy = false }
        do {
            if configuration.demo { confirmationState.receive(previous); return }
            let response = try await ConnectionStore.client(configuration).json("/api/chat/task/confirmation", body: .object([
                "conversation_id": .number(Double(cid)), "task_id": .string(previous.taskID)
            ]))
            guard response["task_id"].string == previous.taskID else { throw AgentError.protocolViolation }
            if response["confirmation"] == .null {
                confirmationState.clear()
                error = "服务端当前没有这项任务的有效确认卡。请核对执行结果，不要重发旧批准请求。"
            } else {
                let card = try Confirmation(response["confirmation"])
                guard card.taskID == previous.taskID else { throw AgentError.protocolViolation }
                confirmationState.receive(card)
            }
        } catch { self.error = error.localizedDescription }
    }

    private func demoReply(message: String, approving: Confirmation?, index: Int) async throws {
        currentConversation = -1
        let reply: String
        if approving != nil {
            reply = "演示确认已收到，喵。没有修改真实博客数据。"
        } else if message.contains("审核") || message.contains("事务") {
            let now = Date().timeIntervalSince1970
            confirmationState.receive(try Confirmation(.object([
                "id": .string(UUID().uuidString), "task_id": .string("demo-task"),
                "q": .string("通过这条演示留言吗？"), "token": .string("demo-only"),
                "exp": .number(now + 300), "server_time": .number(now),
                "opts": .array([.object(["label": .string("确认通过"), "value": .string("yes")]),
                                .object(["label": .string("撤销"), "value": .string("no")])]),
                "details": .object(["fields": .array([.object(["label": .string("留言内容"), "value": .string("泠月喵，晚上好！")])]), "sections": .array([])]),
                "notices": .array([.object(["kind": .string("info"), "text": .string("这是一张演示卡，不会提交真实操作。")])])
            ])))
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
            try appendText(String(character))
        }
    }
}

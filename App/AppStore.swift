import ActivityKit
import Foundation
import LingyueCore
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    typealias Message = ChatMessage
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
    @Published var conversationsPresented = false
    @Published var composerDraft = ""
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var loadingConversations = false
    @Published private(set) var conversationListError: String?
    @Published private(set) var historyNotice: String?
    @Published private(set) var viewingEarlierHistory = false
    @Published private(set) var historyScrollAnchor: String?
    private var historyWindow: HistoryWindow?
    private var listRequest = UUID()
    private var conversationSelectionInitialized = false
    private var drafts: [Int: String] = [:]
    private var draftOrder: [Int] = []
    private var reviews: [Int: ConfirmationReviewState] = [:]
    private var reviewOrder: [Int] = []
    private var demoHistories: [Int: [Message]] = [:]
    private var nextDemoID = -1
    var conversationTitle: String { conversations.first { $0.id == currentConversation }?.displayTitle ?? (currentConversation == nil ? "新对话" : "泠月喵") }
    var hasOlderHistory: Bool { historyWindow?.mayHaveOlder == true }
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
        conversations = []; drafts = [:]; reviews = [:]; demoHistories = [:]
        conversationsPresented = false
        draftOrder = []; reviewOrder = []; composerDraft = ""; historyWindow = nil
        conversationSelectionInitialized = false; listRequest = UUID(); loadingConversations = false
        conversationListError = nil; historyNotice = nil; viewingEarlierHistory = false; nextDemoID = -1
        configuration = value
        hasSession = !value.demo && !ConnectionStore.token(for: value.origin).isEmpty
        do { try ConnectionStore.save(value) } catch { self.error = error.localizedDescription }
    }

    func newChat() {
        guard !busy else { return }
        rememberSession()
        activateFreshDraft()
    }

    private func activateFreshDraft() {
        conversationSelectionInitialized = true
        confirmationState.clear(); currentConversation = nil; messages = []; progress = ""
        composerDraft = drafts[0] ?? ""; historyWindow = nil; viewingEarlierHistory = false
        historyNotice = nil; historyScrollAnchor = nil
    }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty else { return }
        guard !viewingEarlierHistory else { error = "请先回到最新消息，再发送或处理事务。"; return }
        guard text.unicodeScalars.count <= 4000 else { error = "每条消息最多 4000 字。"; return }
        if configuration.demo, currentConversation == nil, conversations.count >= 20 {
            error = "本地演示最多保留 20 个会话，请删除一个后再试。真实会话由博客保存。"; return
        }
        composerDraft = ""; drafts[currentConversation ?? 0] = nil
        conversationSelectionInitialized = true
        messages.append(Message(user: true, text: text))
        confirmationState.clear()
        startStream(message: text)
    }

    func approve(_ card: Confirmation) {
        guard !busy, !viewingEarlierHistory, confirmationState.canApprove(card) else { return }
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
        guard let cid = task["conversation_id"].int, let id = task["task_id"].string else { return }
        await openConversation(cid, taskID: id)
        if currentConversation == cid { selectedTab = 1 }
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
                    if currentConversation == nil {
                        currentConversation = nextDemoID; nextDemoID -= 1
                        conversations.insert(.init(id: currentConversation!, title: String(message.prefix(32)), createdAt: Date(), updatedAt: Date()), at: 0)
                    }
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
                if configuration.demo {
                    demoHistories[currentConversation!] = messages
                    if let row = conversations.firstIndex(where: { $0.id == currentConversation }) { conversations[row].updatedAt = Date() }
                } else if currentScene == "active", let cid = currentConversation {
                    await synchronizeRecentHistory(cid)
                    await loadConversations()
                }
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
                historyWindow = nil
                historyNotice = "本轮结果未完整确认。切换回来时会重新读取历史和确认状态。"
                if configuration.demo, let cid = currentConversation { demoHistories[cid] = messages }
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
        if messages.count > HistoryWindow.maximumMessages { messages.removeFirst(messages.count - HistoryWindow.maximumMessages) }
        var bytes = messages.reduce(0) { $0 + $1.text.utf8.count }
        while messages.count > 1, bytes > HistoryWindow.maximumBytes { bytes -= messages.removeFirst().text.utf8.count }
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
        let reply: String
        if approving != nil {
            reply = "演示确认已收到，喵。没有修改真实博客数据。"
        } else if message.contains("Markdown") || message.contains("表情") {
            reply = "## 我在这里，喵。\n\n这是 **原生 Markdown** 与离线贴纸演示。\n\n- 正文支持列表、引用和代码\n- 贴纸来自博客内置资源，无需联网\n\n> 今天也一起照看博客吧。\n\n:比心: ![收到](:收到:)\n\n行内代码保持原样：`:比心:`"
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

extension AppStore {
    private func rememberSession() {
        let key = currentConversation ?? 0
        drafts[key] = String(composerDraft.unicodeScalars.prefix(4000))
        draftOrder.removeAll { $0 == key }; draftOrder.append(key)
        while draftOrder.count > 20 { drafts[draftOrder.removeFirst()] = nil }
        guard let cid = currentConversation else { return }
        if configuration.demo { demoHistories[cid] = messages }
        if confirmation != nil {
            var state = confirmationState; state.interrupt(); reviews[cid] = state
            reviewOrder.removeAll { $0 == cid }; reviewOrder.append(cid)
            while reviewOrder.count > 8 { reviews[reviewOrder.removeFirst()] = nil }
        } else { reviews[cid] = nil; reviewOrder.removeAll { $0 == cid } }
    }

    func clampDraft() {
        if composerDraft.unicodeScalars.count > 4000 {
            composerDraft = String(composerDraft.unicodeScalars.prefix(4000))
            error = "每条消息最多 4000 字，超出部分未填入。"
        }
    }

    func setComposerDraft(_ value: String, conversationID: Int?) {
        // A dismissed/reused UIKit editor may commit its previous buffer late.
        // Such an edit must never land in the newly selected conversation.
        guard currentConversation == conversationID else { return }
        composerDraft = value
    }

    func prepareConversations() async {
        await loadConversations()
        guard !conversationSelectionInitialized, !loadingConversations, conversationListError == nil,
              !busy, currentConversation == nil, messages.isEmpty else { return }
        conversationSelectionInitialized = true
        let latest = conversations.max { a, b in
            let left = a.updatedAt ?? .distantPast; let right = b.updatedAt ?? .distantPast
            return left == right ? a.id < b.id : left < right
        }
        if let latest { await openConversation(latest.id) }
    }

    func loadConversations() async {
        guard !loadingConversations else { return }
        if configuration.demo { conversationListError = nil; return }
        let requestID = UUID(); listRequest = requestID
        let scope = generation
        loadingConversations = true
        defer { if listRequest == requestID { loadingConversations = false } }
        do {
            let response = try await ConnectionStore.client(configuration).json("/api/chat/conversations")
            let rows = try Conversation.list(response)
            guard generation == scope, listRequest == requestID else { return }
            conversations = rows; conversationListError = nil
        } catch {
            guard generation == scope, listRequest == requestID else { return }
            conversationListError = error.localizedDescription
        }
    }

    private func currentCard(_ client: BlogClient, cid: Int, taskID: String?) async -> Result<CurrentConfirmation, Error> {
        do {
            var body: [String: JSONValue] = ["conversation_id": .number(Double(cid))]
            if let taskID { body["task_id"] = .string(taskID) }
            let response = try await client.json("/api/chat/task/confirmation", body: .object(body))
            return .success(try CurrentConfirmation(response, taskID: taskID))
        } catch { return .failure(error) }
    }

    func openConversation(_ cid: Int, taskID: String? = nil) async {
        guard !busy else { return }
        if configuration.demo {
            guard conversations.contains(where: { $0.id == cid }) else { return }
            rememberSession()
            currentConversation = cid; messages = demoHistories[cid] ?? []
            confirmationState = reviews[cid] ?? .init()
            composerDraft = drafts[cid] ?? ""; historyWindow = nil
            viewingEarlierHistory = false; historyNotice = nil; historyScrollAnchor = nil
            conversationSelectionInitialized = true
            return
        }
        guard cid > 0 else { return }
        busy = true; defer { busy = false }
        let scope = generation
        do {
            let client = try ConnectionStore.client(configuration)
            async let projection = currentCard(client, cid: cid, taskID: taskID)
            let page = try await client.history(conversationID: cid)
            let result = await projection
            guard generation == scope else { return }
            rememberSession()
            let window = try HistoryWindow(page: page)
            currentConversation = cid; historyWindow = window; messages = window.items
            composerDraft = drafts[cid] ?? ""; viewingEarlierHistory = false
            historyNotice = nil; historyScrollAnchor = nil; conversationSelectionInitialized = true
            confirmationState = reviews[cid] ?? .init()
            switch result {
            case .success(let projection):
                if let card = projection.card { confirmationState.receive(card) }
                else { confirmationState.clear() }
            case .failure:
                confirmationState.interrupt()
                historyNotice = "历史已载入，当前确认状态暂未核对成功。已保留的卡仅供查看，请重新核对后批准。"
            }
        } catch { if generation == scope { self.error = error.localizedDescription } }
    }

    func loadEarlierHistory() async {
        guard !busy, let cid = currentConversation, var window = historyWindow,
              window.mayHaveOlder, let before = window.oldestID else { return }
        busy = true; defer { busy = false }
        let scope = generation
        let anchor = messages.first?.id
        do {
            let page = try await ConnectionStore.client(configuration).history(conversationID: cid, beforeID: before)
            guard generation == scope, currentConversation == cid else { return }
            try window.prepend(page)
            if !page.items.isEmpty { viewingEarlierHistory = true }
            historyWindow = window; messages = window.items
            historyNotice = window.droppedNewer ? "仅保留当前历史窗口，回到最新后可继续聊天。" : nil
            historyScrollAnchor = anchor
        } catch { if generation == scope { self.error = error.localizedDescription } }
    }

    func returnToLatest() async {
        guard let cid = currentConversation else { return }
        await openConversation(cid)
    }

    private func synchronizeRecentHistory(_ cid: Int) async {
        let scope = generation
        do {
            let page = try await ConnectionStore.client(configuration).history(conversationID: cid)
            guard generation == scope, currentConversation == cid else { return }
            guard !page.items.isEmpty else { throw AgentError.invalidResponse }
            let window = try HistoryWindow(page: page)
            historyWindow = window; messages = window.items; historyNotice = nil
        } catch {
            historyWindow = nil
            historyNotice = "最新历史暂未同步，当前回复仍保留在本机。可重新读取最新记录；不会重发消息。"
        }
    }

    func updateConversation(_ conversation: Conversation, title: String? = nil, pinned: Bool? = nil) async {
        guard !busy, title != nil || pinned != nil else { return }
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, title.isEmpty || title.unicodeScalars.count > 64 { error = "会话标题请填写 1–64 字。"; return }
        busy = true; defer { busy = false }
        listRequest = UUID(); loadingConversations = false
        do {
            if !configuration.demo {
                var body: [String: JSONValue] = [:]
                if let title { body["title"] = .string(title) }
                if let pinned { body["pinned"] = .bool(pinned) }
                let response = try await ConnectionStore.client(configuration).json("/api/chat/conversations/\(conversation.id)", body: .object(body), method: .patch)
                guard response["success"].bool == true else { throw AgentError.invalidResponse }
            }
            if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                if let title { conversations[index].title = title }
                if let pinned { conversations[index].pinned = pinned }
            }
            if configuration.demo {
                conversations.sort { a, b in a.pinned != b.pinned ? a.pinned : (a.updatedAt ?? .distantPast) > (b.updatedAt ?? .distantPast) }
            } else { await loadConversations() }
        } catch { self.error = error.localizedDescription }
    }

    func deleteConversation(_ conversation: Conversation) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        listRequest = UUID(); loadingConversations = false
        do {
            if !configuration.demo {
                let response = try await ConnectionStore.client(configuration).json("/api/chat/conversations/\(conversation.id)", method: .delete)
                guard response["success"].bool == true else { throw AgentError.invalidResponse }
            }
            conversations.removeAll { $0.id == conversation.id }
            drafts[conversation.id] = nil; reviews[conversation.id] = nil; demoHistories[conversation.id] = nil
            draftOrder.removeAll { $0 == conversation.id }; reviewOrder.removeAll { $0 == conversation.id }
            if currentConversation == conversation.id { activateFreshDraft() }
            if !configuration.demo { await loadConversations() }
        } catch { self.error = error.localizedDescription }
    }
}

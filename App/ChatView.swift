import LingyueCore
import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: AppStore
    @State private var approving: Confirmation?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        historyControls
                        if store.messages.isEmpty {
                            VStack(spacing: 18) {
                                LingyueAvatar(size: 120)
                                Text("我在呢，喵。").font(.title2.bold())
                                Text(store.configuration.demo ? "本地演示 · 回复为预设内容" : "随便聊聊，或者把博客交给我看看。")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                ForEach(["看看服务器状态", "博客最近有什么动态", "看看 Markdown 和表情", "演示一下审核事务"], id: \.self) { prompt in
                                    if store.configuration.demo || !prompt.contains("演示") {
                                        Button(prompt) { store.send(prompt) }.buttonStyle(.bordered).disabled(store.busy)
                                    }
                                }
                            }.frame(maxWidth: .infinity).padding(.vertical, 38)
                        }
                        ForEach(Array(store.messages.enumerated()), id: \.element.id) { index, message in
                            if ChatTime.shouldShow(previous: index > 0 ? store.messages[index - 1].time : nil, current: message.time), let time = message.time {
                                ChatTimestamp(time: time, day: Calendar.current.startOfDay(for: Date())).equatable()
                            }
                            ChatMessageRow(message: message,
                                userName: store.configuration.demo ? "我 · 演示" : store.profile?.displayName ?? "我",
                                profile: store.profile, origin: store.configuration.origin).equatable().id(message.id)
                        }
                        if let card = store.confirmation, !store.viewingEarlierHistory {
                            confirmationCard(card)
                        }
                        if store.busy { HStack { ProgressView(); Text(store.receiving ? store.progress : "读取中…").font(.caption).foregroundStyle(.secondary) } }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(18)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .onChange(of: store.messages.last?.text) { _, _ in if !store.viewingEarlierHistory { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: store.messages.last?.id) { _, _ in if !store.viewingEarlierHistory { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: store.confirmation?.id) { _, _ in if !store.viewingEarlierHistory { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: store.viewingEarlierHistory) { _, earlier in if !earlier { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: store.historyScrollAnchor) { _, anchor in if let anchor { proxy.scrollTo(anchor, anchor: .top) } }
            }
            .safeAreaInset(edge: .bottom) {
                if store.viewingEarlierHistory {
                    HStack {
                        Label("正在查看较早消息", systemImage: "clock").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button("回到最新消息") { Task { await store.returnToLatest() } }.disabled(store.busy)
                    }.padding().background(.regularMaterial)
                } else {
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("和泠月喵说点什么…", text: draftBinding, axis: .vertical)
                        .id(store.currentConversation ?? 0)
                        .accessibilityIdentifier("chat.composer")
                        .lineLimit(1...5).focused($focused).padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                        .disabled(store.busy)
                    if store.receiving {
                        Button { store.stopReceiving() } label: { Image(systemName: "stop.circle.fill").font(.title) }
                            .accessibilityLabel("停止接收回复")
                    } else {
                        Button {
                            focused = false; store.send(store.composerDraft)
                        } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .disabled(store.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .disabled(store.busy)
                        .accessibilityLabel("发送消息")
                    }
                }.padding(.horizontal, 18).padding(.vertical, 10).background(.regularMaterial)
                }
            }
            .navigationTitle((store.configuration.demo ? "演示 · " : "") + store.conversationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { store.observeChatVisibility(true) }
            .onDisappear { store.observeChatVisibility(false) }
            .task { await store.prepareConversations() }
            .onChange(of: store.composerDraft) { _, _ in store.clampDraft() }
            .onChange(of: store.currentConversation) { _, _ in approving = nil; focused = false }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("会话列表", systemImage: "list.bullet.bubble") { focused = false; store.conversationsPresented = true }
                        .accessibilityIdentifier("chat.conversations")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新对话", systemImage: "square.and.pencil") { store.newChat() }.disabled(store.busy)
                }
            }
            .sheet(isPresented: $store.conversationsPresented) { ConversationsView().environmentObject(store) }
            .confirmationDialog("提交这项操作？", isPresented: Binding(get: { approving != nil }, set: { if !$0 { approving = nil } })) {
                Button("确认提交") { if let card = approving { store.approve(card) }; approving = nil }
            } message: { Text(approving?.question ?? "") }
        }
    }

    private var draftBinding: Binding<String> {
        let cid = store.currentConversation
        return Binding(get: { store.currentConversation == cid ? store.composerDraft : "" },
                       set: { store.setComposerDraft($0, conversationID: cid) })
    }

    @ViewBuilder private var historyControls: some View {
        if store.currentConversation != nil, !store.configuration.demo {
            VStack(spacing: 10) {
                if store.hasOlderHistory {
                    Button("加载更早消息", systemImage: "clock.arrow.circlepath") { Task { await store.loadEarlierHistory() } }
                        .font(.footnote).disabled(store.busy)
                }
                if let notice = store.historyNotice {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                }
                Button(store.viewingEarlierHistory ? "回到最新消息" : "重新读取最新记录") { Task { await store.returnToLatest() } }
                    .font(.caption).disabled(store.busy)
            }.frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func confirmationCard(_ card: Confirmation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("需要你审阅", systemImage: "hand.raised").font(.caption.bold()).foregroundStyle(.purple)
            Text(verbatim: card.question).font(.headline)
            ForEach(Array((card.details["fields"].array ?? []).enumerated()), id: \.offset) { _, field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: field["label"].string ?? "").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: field["value"].string ?? "").textSelection(.enabled)
                }
            }
            ForEach(Array((card.details["sections"].array ?? []).enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: section["label"].string ?? "").font(.subheadline.bold())
                    // Literal rendering preserves complete review content and prevents embedded actions.
                    Text(verbatim: section["text"].string ?? "").textSelection(.enabled)
                }
            }
            ForEach(card.notices, id: \.self) { Text(verbatim: $0).font(.caption).foregroundStyle(.secondary) }
            if !card.supportsNativeReview {
                Text("这张卡需要图片审阅或批量选择，请在博客中继续。").font(.footnote)
                Link("打开博客", destination: URL(string: store.configuration.origin)!)
            }
            if store.confirmationState.requiresRefresh {
                Text("上一轮未能确认完整结果。这张卡仅保留供核对，重新读取服务端状态后才能批准。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("重新核对确认状态") { Task { await store.reloadConfirmation() } }
                    .buttonStyle(.bordered).disabled(store.busy)
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    if card.expired { Text("确认卡已过期，请到事务页重新读取。").font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        ForEach(card.options.filter { $0.value == "yes" || $0.value == "no" }) { option in
                            if option.value == "no" {
                                Button(option.label) { Task { await store.cancelConfirmation(card) } }.buttonStyle(.bordered).disabled(store.busy)
                            } else if card.supportsNativeReview {
                                Button(option.label) { approving = card }.buttonStyle(.borderedProminent)
                                    .disabled(store.busy || !store.confirmationState.canApprove(card))
                            }
                        }
                    }
                }
            }
            if card.options.contains(where: { $0.value == "other" }) {
                Text("想调整内容，可以直接在输入框提出新要求。").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
    }
}

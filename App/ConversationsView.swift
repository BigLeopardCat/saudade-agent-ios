import LingyueCore
import SwiftUI

struct ConversationsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var renaming: Conversation?
    @State private var title = ""
    @State private var deleting: Conversation?
    private var rows: [Conversation] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? store.conversations : store.conversations.filter { $0.displayTitle.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        NavigationStack {
            List {
                if store.busy {
                    Section {
                        Text(store.receiving ? "正在接收回复。结束或手动停止后可切换会话。" : "正在读取或更新，请稍候。")
                            .font(.footnote).foregroundStyle(.secondary)
                        if store.receiving { Button("停止当前接收") { store.stopReceiving() } }
                    }
                }
                if let error = store.conversationListError {
                    Section { Text(error).font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    if rows.isEmpty {
                        Text(store.loadingConversations ? "正在读取会话…" : "暂无匹配会话，开启一段新对话吧。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rows) { conversation in conversationRow(conversation) }
                } footer: {
                    Text(store.configuration.demo ? "演示会话仅保存在本次运行内。" : "会话保存在你的博客，最多展示最近 200 个。历史按页读取，切换不会自动发送消息。")
                }
            }
            .navigationTitle("会话")
            .searchable(text: $search, prompt: "搜索会话标题")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("新对话", systemImage: "square.and.pencil") { store.newChat(); dismiss() }.disabled(store.busy)
                        .accessibilityIdentifier("conversations.new")
                }
            }
            .task { await store.loadConversations() }
            .refreshable { if !store.busy { await store.loadConversations() } }
            .sheet(item: $renaming) { conversation in renameForm(conversation) }
            .confirmationDialog("删除这个会话？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("删除会话", role: .destructive) {
                    if let conversation = deleting { Task { await store.deleteConversation(conversation) } }
                    deleting = nil
                }
            } message: { Text("会删除会话历史并清理关联状态，无法撤销。已经发生的博客操作不会回滚。") }
            .alert("会话操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("知道了") { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }
    private func renameForm(_ conversation: Conversation) -> some View {
        NavigationStack {
            Form { TextField("会话标题（1–64 字）", text: $title) }
                .navigationTitle("重命名会话")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { renaming = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            let value = title; renaming = nil
                            Task { await store.updateConversation(conversation, title: value) }
                        }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.unicodeScalars.count > 64 || store.busy)
                    }
                }
        }.presentationDetents([.medium])
    }
    private func conversationRow(_ conversation: Conversation) -> some View {
        Button {
            Task {
                await store.openConversation(conversation.id)
                if store.currentConversation == conversation.id && store.error == nil { dismiss() }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: conversation.pinned ? "pin.fill" : "bubble.left.and.bubble.right")
                    .foregroundStyle(.purple).frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: conversation.displayTitle).font(.subheadline.weight(.medium)).lineLimit(2)
                    if let date = conversation.updatedAt { Text(ChatTime.label(date)).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if store.currentConversation == conversation.id { Image(systemName: "checkmark").foregroundStyle(.purple) }
            }.padding(.vertical, 5)
        }
        .buttonStyle(.plain).disabled(store.busy)
        .accessibilityIdentifier("conversation.row.\(conversation.id)")
        .contextMenu {
            Button("重命名", systemImage: "pencil") { title = conversation.title ?? ""; renaming = conversation }.disabled(store.busy)
            Button(conversation.pinned ? "取消置顶" : "置顶", systemImage: "pin") {
                Task { await store.updateConversation(conversation, pinned: !conversation.pinned) }
            }.disabled(store.busy)
            Button("删除", systemImage: "trash", role: .destructive) { deleting = conversation }.disabled(store.busy)
        }
    }
}

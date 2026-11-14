import LingyueCore
import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var store: AppStore
    @State private var pendingCancellation: JSONValue?
    var body: some View {
        NavigationStack {
            List {
                introduction
                if let work = store.overview?.work {
                    ForEach(WorkQueue.Kind.allCases, id: \.self) { WorkCategorySection(work: work, kind: $0) }
                    if !work.issues.isEmpty {
                        Section("读取状态") {
                            ForEach(work.issues, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                } else { Section { ProgressView("正在读取人工待办…") } }
                pausedExecutions
                Section {
                    Link("前往博客后台", destination: URL(string: store.configuration.origin + "/dashboard")!)
                    Text("生图、封面和批量选择请回博客审阅。取消接收或取消 Agent 执行不会撤销已经发生的业务操作。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("待处理事务")
                .refreshable { await store.refresh() }
                .confirmationDialog("取消这个暂停的 Agent 执行？", isPresented: Binding(get: { pendingCancellation != nil }, set: { if !$0 { pendingCancellation = nil } })) {
                    Button("取消执行", role: .destructive) {
                        if let task = pendingCancellation { Task { await store.cancelTask(task) } }
                        pendingCancellation = nil
                    }
                } message: { Text("已执行的业务操作会保留。") }
        }
    }
    private var introduction: some View {
        Section {
            Text("评论、留言和额度申请等需要你人工决定的事项。读取和审阅不会自动批准。")
                .font(.subheadline).foregroundStyle(.secondary)
            if store.configuration.demo { Label("演示数据，不会修改博客", systemImage: "sparkles").font(.caption) }
        }
    }
    @ViewBuilder private var pausedExecutions: some View {
        if let overview = store.overview, !overview.tasks.isEmpty {
            Section("暂停的 Agent 执行 · 继续审阅") {
                ForEach(overview.tasks, id: \.self) { task in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(task["title"].string ?? "待继续的 Agent 执行")
                        HStack {
                            Button("查看并审阅") { Task { await store.openTask(task) } }.buttonStyle(.bordered)
                            Button("取消执行", role: .destructive) { pendingCancellation = task }.buttonStyle(.bordered)
                        }.disabled(store.busy)
                    }.padding(.vertical, 5)
                }
            }
        }
    }
}

private struct WorkCategorySection: View {
    let work: WorkQueue
    let kind: WorkQueue.Kind
    private var items: [WorkQueue.Item] { work.items.filter { $0.kind == kind } }
    private var title: String { kind.title + " · " + (work.counts[kind].map { String($0) } ?? "未知") }
    var body: some View {
        Section(title) {
            if items.isEmpty {
                Text(work.counts[kind] == 0 ? "暂无待处理事项" : "列表暂不可用，请刷新或到博客核对")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(items) { WorkItemRow(item: $0) }
            if let total = work.counts[kind], total > items.count {
                Text("展示最近 \(items.count) / \(total) 项，更多事项可在博客后台查看。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct WorkItemRow: View {
    @EnvironmentObject private var store: AppStore
    let item: WorkQueue.Item
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("#\(item.number) · \(item.author)").font(.subheadline.weight(.medium))
                Spacer()
                Text("待人工审阅").font(.caption).foregroundStyle(.secondary)
            }
            Text(verbatim: item.preview).font(.subheadline).lineLimit(4)
            Button("交给泠月喵读取完整内容") {
                store.selectedTab = 1
                store.send(store.configuration.demo ? "演示一下审核事务" : item.reviewPrompt)
            }.buttonStyle(.bordered).disabled(store.busy)
        }.padding(.vertical, 5)
    }
}

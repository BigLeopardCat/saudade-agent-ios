import LingyueCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView(selection: $store.selectedTab) {
            OverviewView().tabItem { Label("陪伴", systemImage: "moon.stars") }.tag(0)
            ChatView().tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right") }.tag(1)
            TasksView().tabItem { Label("事务", systemImage: "checklist") }.tag(2)
            SettingsView().tabItem { Label("连接", systemImage: "slider.horizontal.3") }.tag(3)
        }
        .alert("泠月喵提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("知道了") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

private struct OverviewView: View {
    @EnvironmentObject private var store: AppStore
    private let ink = Color(red: 0.13, green: 0.12, blue: 0.20)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Label("SAUDADE / COMPANION", systemImage: "sparkle")
                            .font(.caption2.monospaced()).tracking(1.5)
                        Spacer()
                        if store.configuration.demo { Text("演示模式").font(.caption).padding(6).background(.purple.opacity(0.1), in: Capsule()) }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("月光落在\n你的灵动岛。")
                                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                                Text("泠月喵，随身陪你照看博客。")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            LingyueAvatar(size: 106).padding(.top, 18)
                        }
                        Divider().overlay(.white.opacity(0.3))
                        Label(store.overview?.summary ?? "正在看看博客…", systemImage: "waveform.path.ecg")
                            .font(.subheadline)
                        if let overview = store.overview {
                            Text("观测于 \(overview.observedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(22)
                    .background(LinearGradient(colors: [Color(red: 0.91, green: 0.87, blue: 0.98), .white], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))

                    HStack(spacing: 12) {
                        Button { Task {
                            if store.islandActive { await store.endIsland() }
                            else { await store.startIsland() }
                        } } label: {
                            Label(store.islandActive ? "结束陪伴" : "开始灵动岛陪伴", systemImage: store.islandActive ? "moon.zzz" : "sparkles")
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                        }.buttonStyle(.borderedProminent).disabled(store.busy)
                        Button { store.selectedTab = 1 } label: {
                            Image(systemName: "bubble.left").padding(.vertical, 6)
                        }.buttonStyle(.bordered).accessibilityLabel("和泠月喵聊天")
                    }

                    if let overview = store.overview {
                        if !overview.metrics.isEmpty {
                            HStack {
                                ForEach(overview.metrics) { metric in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(metric.id).font(.caption).foregroundStyle(.secondary)
                                        Text(metric.value).font(.title3.bold().monospacedDigit())
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20))
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            Text("博客近期文章").font(.headline)
                            if overview.articles.isEmpty { Text("暂无可展示的文章").foregroundStyle(.secondary) }
                            ForEach(overview.articles) { article in
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.text").foregroundStyle(.purple).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(article.title).font(.subheadline.weight(.medium))
                                        Text(article.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20))
                        ForEach(overview.issues, id: \.self) { issue in
                            Label(issue, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("一次陪伴，一段值守。状态按需更新，打开应用可重新开始实时活动。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(22)
            }
            .foregroundStyle(ink)
            .background(Color(red: 0.97, green: 0.96, blue: 0.98))
            .navigationTitle("泠月喵").navigationBarTitleDisplayMode(.inline)
            .refreshable { await store.refresh() }
        }
    }
}

private struct TasksView: View {
    @EnvironmentObject private var store: AppStore
    @State private var pendingCancellation: JSONValue?

    var body: some View {
        NavigationStack {
            List {
                if store.configuration.demo {
                    Section {
                        Text("体验一次“准备 → 审阅 → 确认”的事务流程。演示不会修改博客。")
                        Button("让泠月喵准备一项演示事务") { store.selectedTab = 1; store.send("演示一下审核事务") }
                            .disabled(store.busy)
                    }
                }
                Section("暂停的 Agent 任务") {
                    if let overview = store.overview {
                        if !overview.tasksAvailable { Label("任务服务暂时不可用", systemImage: "wifi.exclamationmark") }
                        else if overview.tasks.isEmpty { Text("目前没有暂停任务").foregroundStyle(.secondary) }
                        ForEach(Array(overview.tasks.enumerated()), id: \.offset) { _, task in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(task["title"].string ?? "待处理任务")
                                HStack {
                                    Button("查看并审阅") { Task { await store.openTask(task) } }.buttonStyle(.bordered)
                                    Button("取消任务", role: .destructive) { pendingCancellation = task }.buttonStyle(.bordered)
                                }.disabled(store.busy)
                            }.padding(.vertical, 6)
                        }
                    } else { ProgressView() }
                }
                Section {
                    Text("文本操作可在对话中确认。生图、封面和批量选择请回博客审阅。取消任务不会撤销已经发生的业务操作。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("事务")
            .refreshable { await store.refresh() }
            .confirmationDialog("取消这个暂停任务？", isPresented: Binding(get: { pendingCancellation != nil }, set: { if !$0 { pendingCancellation = nil } })) {
                Button("取消任务", role: .destructive) {
                    if let task = pendingCancellation { Task { await store.cancelTask(task) } }
                    pendingCancellation = nil
                }
            } message: { Text("已执行的业务操作会保留。") }
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var origin = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("当前连接") {
                    Label(store.configuration.demo ? "本地演示" : store.configuration.origin, systemImage: store.configuration.demo ? "sparkles" : "network")
                    if store.configuration.demo { Text("聊天和指标均为模拟数据。真实模式会连接你的博客与现有 Agent。").font(.footnote).foregroundStyle(.secondary) }
                }
                Section("登录博客") {
                    TextField("https://你的博客", text: $origin).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("账号", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("密码", text: $password).textContentType(.password)
                    Button(store.busy ? "连接中…" : "登录并连接") {
                        let suppliedPassword = password
                        password = ""
                        Task { await store.connect(origin: origin, username: username, password: suppliedPassword) }
                    }.disabled(store.busy || store.refreshing || username.isEmpty || password.isEmpty)
                    if !store.configuration.demo {
                        Button("退出登录", role: .destructive) { Task { await store.logout() } }.disabled(store.busy || store.refreshing)
                    }
                }
                Section {
                    Button("使用本地演示") { Task { await store.useDemo() } }.disabled(store.busy || store.refreshing)
                    Text("登录凭据保存在本机钥匙串。服务器诊断需要管理员权限。").font(.footnote).foregroundStyle(.secondary)
                }
                Section("关于泠月喵") {
                    LingyueAvatar(size: 90)
                    Text("形象：BigLeopardCat / saudade-blog-agent\n美术许可：CC BY-NC-SA 4.0").font(.footnote)
                    Link("原项目与美术署名", destination: URL(string: "https://github.com/BigLeopardCat/saudade-blog-agent")!)
                    Link("美术资源许可", destination: URL(string: "https://github.com/BigLeopardCat/saudade-blog-agent/blob/main/frontend/ASSETS-LICENSE.md")!)
                }
            }.navigationTitle("连接")
                .onAppear { if origin.isEmpty { origin = store.configuration.origin } }
        }
    }
}

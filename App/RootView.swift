import LingyueCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView(selection: $store.selectedTab) {
            OverviewView().tabItem { Label("陪伴", systemImage: "moon.stars") }.tag(0)
            ChatView().tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right") }.tag(1)
            TasksView().tabItem { Label("事务", systemImage: "checklist") }.badge(store.overview?.work.knownTotal ?? 0).tag(2)
            SettingsView().tabItem { Label("连接", systemImage: "slider.horizontal.3") }.tag(3)
        }
        .onReceive(NotificationCenter.default.publisher(for: .companionEnded).receive(on: RunLoop.main)) { _ in store.companionEnded() }
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
                            if store.islandActive || store.receiving { await store.endIsland() }
                            else { await store.startIsland() }
                        } } label: {
                            Label(store.islandActive || store.receiving ? "结束陪伴" : "开始灵动岛陪伴", systemImage: store.islandActive || store.receiving ? "moon.zzz" : "sparkles")
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                        }.buttonStyle(.borderedProminent).disabled(store.busy && !store.islandActive && !store.receiving)
                        Button { store.selectedTab = 1 } label: {
                            Image(systemName: "bubble.left").padding(.vertical, 6)
                        }.buttonStyle(.bordered).accessibilityLabel("和泠月喵聊天")
                    }

                    if let overview = store.overview {
                        Button { store.selectedTab = 2 } label: {
                            HStack {
                                Label("需要你处理", systemImage: "tray.full")
                                Spacer()
                                Text(overview.work.total.map { "\($0) 项" } ?? "至少 \(overview.work.knownTotal) 项 · 部分未知")
                                    .font(.subheadline)
                                Image(systemName: "chevron.right").font(.caption)
                            }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain)
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

private struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showLogin = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        IdentityAvatar(profile: store.profile, origin: store.configuration.origin, size: 64)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.configuration.demo ? "本地演示" : store.profile?.displayName ?? (store.hasSession ? "已保存登录" : "尚未登录")).font(.headline)
                            if let profile = store.profile { Text("@" + profile.username).font(.caption).foregroundStyle(.secondary) }
                            Text(store.configuration.demo ? "模拟聊天与博客指标" : store.configuration.origin)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                    if let notice = store.identityNotice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                    Button(store.hasSession ? "切换账号或重新登录" : "登录我的博客") { showLogin = true }
                        .disabled(store.busy || store.refreshing)
                    if store.hasSession {
                        Button("退出登录", role: .destructive) { Task { await store.logout() } }.disabled(store.busy || store.refreshing)
                    }
                    if !store.configuration.demo {
                        Button("使用本地演示") { Task { await store.useDemo() } }.disabled(store.busy || store.refreshing)
                    }
                } footer: {
                    Text("支持连接自己部署的兼容 Saudade Blog 与 Agent。密码仅用于登录，令牌保存在本机钥匙串。")
                }
                Section("陪伴与电量") {
                    Button("结束陪伴与当前接收", role: .destructive) { Task { await store.endIsland() } }
                    Text("立即移除灵动岛和锁屏实时活动，停止当前接收。没有后台定时轮询；结束后仅在你主动使用 App 时联网。远端已经开始的操作可能仍会继续，需要核对结果。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("灵动岛不支持键盘输入。自由聊天会打开 App，展开区可直接刷新或结束陪伴。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("关于泠月喵") {
                    LabeledContent("构建版本", value: BuildInfo.label).font(.footnote)
                    ShareLink("导出聊天诊断日志", item: ChatLogStore.shared.fileURL)
                    Text("日志只含请求编号、事件名、生命周期、错误代码和耗时。聊天、确认凭据和令牌不会写入日志。")
                        .font(.footnote).foregroundStyle(.secondary)
                    LingyueAvatar(size: 90)
                    Text("形象：BigLeopardCat / saudade-blog-agent\n美术许可：CC BY-NC-SA 4.0").font(.footnote)
                    Link("原项目与美术署名", destination: URL(string: "https://github.com/BigLeopardCat/saudade-blog-agent")!)
                    Link("美术资源许可", destination: URL(string: "https://github.com/BigLeopardCat/saudade-blog-agent/blob/main/frontend/ASSETS-LICENSE.md")!)
                }
            }.navigationTitle("我的博客")
                .sheet(isPresented: $showLogin) { BlogLoginView().environmentObject(store) }
        }
    }
}

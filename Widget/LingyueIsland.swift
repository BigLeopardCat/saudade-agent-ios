import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LingyueWidgets: WidgetBundle {
    var body: some Widget { LingyueIsland() }
}

struct LingyueIsland: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CompanionAttributes.self) { context in
            HStack(spacing: 14) {
                LingyueAvatar(size: 62)
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.state.demo ? "泠月喵 · 演示陪伴" : "泠月喵 · 博客值守").font(.caption).foregroundStyle(.secondary)
                    Text(context.isStale ? "状态待更新，喵。" : context.state.headline).font(.headline).privacySensitive()
                    Text(context.state.detail).font(.caption).foregroundStyle(.secondary).privacySensitive()
                }
                Spacer(minLength: 0)
                Button(intent: RefreshCompanionIntent()) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).accessibilityLabel("刷新博客状态")
            }
            .padding(18)
            .activityBackgroundTint(Color(red: 0.11, green: 0.09, blue: 0.17))
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
            .widgetURL(URL(string: "lingyue://overview")!)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { LingyueAvatar(size: 46) }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(context.state.demo ? "演示" : "值守中").font(.caption2).foregroundStyle(.secondary)
                        status(context)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(context.isStale ? "状态待更新，喵。" : context.state.headline)
                            .font(.subheadline).lineLimit(2).privacySensitive()
                        HStack {
                            Button(intent: RefreshCompanionIntent()) { Label("看看状态", systemImage: "arrow.clockwise") }
                                .buttonStyle(.bordered)
                            Link(destination: URL(string: "lingyue://chat")!) { Label("和我聊聊", systemImage: "bubble.left") }
                                .buttonStyle(.bordered)
                            Spacer(minLength: 0)
                            if let count = context.state.pendingCount, count > 0 {
                                Link(destination: URL(string: "lingyue://tasks")!) {
                                    Text("\(count) 项待办").font(.caption).privacySensitive()
                                }
                            }
                        }.font(.caption)
                    }
                }
            } compactLeading: {
                LingyueAvatar(size: 28)
            } compactTrailing: {
                status(context)
            } minimal: {
                LingyueAvatar(size: 24)
            }
            .widgetURL(URL(string: "lingyue://chat")!)
            .keylineTint(.purple)
        }
    }

    @ViewBuilder private func status(_ context: ActivityViewContext<CompanionAttributes>) -> some View {
        let stale = context.isStale || context.state.healthy == nil
        Image(systemName: stale ? "questionmark.circle" : (context.state.healthy == true ? "checkmark.circle.fill" : "exclamationmark.circle.fill"))
            .foregroundStyle(stale ? .gray : (context.state.healthy == true ? .mint : .orange))
            .accessibilityLabel(stale ? "状态待更新" : (context.state.healthy == true ? "服务正常" : "服务需留意"))
    }
}

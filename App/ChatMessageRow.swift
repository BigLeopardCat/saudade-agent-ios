import LingyueCore
import SwiftUI

struct ChatMessageRow: View, Equatable {
    let message: ChatMessage
    let userName: String
    let profile: UserProfile?
    let origin: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.user { Spacer(minLength: 30) }
            else { LingyueAvatar(size: 34) }
            VStack(alignment: message.user ? .trailing : .leading, spacing: 6) {
                Text(message.user ? userName : "泠月喵")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                VStack(alignment: .leading, spacing: 8) {
                    if message.user { Text(verbatim: message.text).textSelection(.enabled) }
                    else { ChatMarkdown(text: message.text).equatable() }
                    if message.imageCount > 0 {
                        Label("含 \(message.imageCount) 张图片，请到博客查看", systemImage: "photo")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if message.truncated {
                        Text("这条长消息仅展示节选，完整内容请到博客查看。")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("打开博客", destination: URL(string: origin)!)
                            .font(.caption)
                    }
                    if message.incomplete {
                        Label("本轮未完整结束", systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(message.user ? Color.purple.opacity(0.13) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            }
            if message.user { IdentityAvatar(profile: profile, origin: origin, size: 34) }
            else { Spacer(minLength: 12) }
        }
    }
}

struct ChatTimestamp: View, Equatable {
    let time: Date
    let day: Date
    var body: some View {
        Text(ChatTime.label(time, now: day)).font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).padding(.vertical, 5)
    }
}

import SwiftUI
import LingyueCore

/// Native adaptation of Saudade-Blog cn_sora_blog /frontend/src/pages/Login.
struct BlogLoginView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var origin = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var submitted = false
    private var dark: Bool { scheme == .dark }
    private var ink: Color { dark ? Color(red: 0.94, green: 0.91, blue: 0.85) : Color(red: 0.29, green: 0.21, blue: 0.31) }
    private var actionColors: [Color] { dark ? [Color(red: 0.97, green: 0.86, blue: 0.68), Color(red: 0.91, green: 0.72, blue: 0.40)] : [Color(red: 1, green: 0.84, blue: 0.92), Color(red: 0.94, green: 0.73, blue: 0.87)] }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: dark ? [Color(red: 0.05, green: 0.07, blue: 0.10), Color(red: 0.11, green: 0.15, blue: 0.20)] : [Color(red: 1, green: 0.94, blue: 0.97), Color(red: 0.94, green: 0.92, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                if !dark {
                    Canvas { context, size in
                        var path = Path()
                        for x in stride(from: 0.0, through: size.width, by: 28) { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
                        for y in stride(from: 0.0, through: size.height, by: 28) { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
                        context.stroke(path, with: .color(.purple.opacity(0.08)), lineWidth: 1)
                    }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
                }
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            Text("Saudade Blog").font(.system(size: 24, weight: .semibold)).tracking(1)
                            LingyueAvatar(size: 84).padding(5)
                                .background(dark ? Color.white.opacity(0.04) : .white, in: Circle())
                            Text("与泠月喵一起，照看你的博客").font(.footnote).foregroundStyle(.secondary)
                        }.padding(.bottom, 8)
                        VStack(alignment: .leading, spacing: 18) {
                            field("博客地址") {
                                TextField("https://你的博客", text: $origin).keyboardType(.URL)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                            }
                            field("账号") {
                                TextField("用户名", text: $username).textContentType(.username)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                            }
                            field("密码") {
                                HStack {
                                    Group {
                                        if showPassword { TextField("密码", text: $password) }
                                        else { SecureField("密码", text: $password) }
                                    }.textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
                                    Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye") }
                                        .accessibilityLabel(showPassword ? "隐藏密码" : "显示密码")
                                }
                            }
                        }.disabled(store.busy || submitted)
                        Button {
                            let supplied = password; password = ""; submitted = true
                            Task {
                                await store.connect(origin: origin.trimmingCharacters(in: .whitespacesAndNewlines), username: username, password: supplied)
                                submitted = false
                                if store.hasSession && store.error == nil { dismiss() }
                            }
                        } label: {
                            HStack { if submitted { ProgressView() }; Text(submitted ? "连接中…" : "登 录").tracking(3) }
                                .font(.headline).foregroundStyle(dark ? Color(red: 0.16, green: 0.13, blue: 0.08) : ink)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(LinearGradient(colors: actionColors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
                        }.disabled(submitted || store.busy || store.refreshing || username.isEmpty || password.isEmpty)
                        Text("账号由你所连接博客的管理员开设。忘记密码时，请前往该博客登录页恢复。")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if let connection = try? BlogLoginLink.make(origin) { Link("打开博客登录页", destination: connection).font(.footnote) }
                    }
                    .padding(28).frame(maxWidth: 420)
                    .background(dark ? Color(red: 0.10, green: 0.14, blue: 0.19) : Color(red: 1, green: 0.99, blue: 0.98), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(dark ? .white.opacity(0.12) : .purple.opacity(0.18)))
                    .shadow(color: .black.opacity(dark ? 0.25 : 0.08), radius: 24, y: 12)
                    .padding(24).frame(maxWidth: .infinity).padding(.vertical, 24)
                }.scrollDismissesKeyboard(.interactively)
            }.foregroundStyle(ink)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { password = ""; dismiss() }.disabled(submitted) } }
                .onAppear { if origin.isEmpty { origin = store.configuration.origin } }
        }.interactiveDismissDisabled(submitted)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.medium))
            content().padding(12)
                .background(dark ? .white.opacity(0.04) : .white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(dark ? .white.opacity(0.12) : .purple.opacity(0.15)))
        }
    }
}

private enum BlogLoginLink {
    static func make(_ origin: String) throws -> URL {
        try LingyueCore.BlogConnection(origin: origin, token: "").url("/login")
    }
}

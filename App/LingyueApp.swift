import SwiftUI

@main
struct LingyueApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Color(red: 0.52, green: 0.43, blue: 0.77))
                .task { store.observeScene(scenePhase); await store.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    store.observeScene(phase)
                    if phase == .active { Task { await store.refresh() } }
                }
                .onOpenURL { url in
                    guard url.scheme == "lingyue" else { return }
                    if url.host == "chat" { store.selectedTab = 1 }
                    else if url.host == "tasks" { store.selectedTab = 2 }
                    else { store.selectedTab = 0 }
                }
        }
    }
}

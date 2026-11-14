import ActivityKit
import AppIntents
import Foundation
import LingyueCore

struct CompanionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var headline: String
        var detail: String
        var healthy: Bool?
        var pendingCount: Int?
        var updatedAt: Date
        var demo: Bool
    }
    var name: String
}

extension CompanionAttributes.ContentState {
    init(overview: Overview, demo: Bool) {
        headline = overview.summary
        detail = overview.issues.isEmpty ? "\(overview.articles.count) 篇近期文章" : "部分信息未能更新，打开应用查看"
        healthy = overview.healthy
        pendingCount = overview.tasksAvailable ? overview.tasks.count : nil
        updatedAt = overview.observedAt
        self.demo = demo
    }
}

enum CompanionActivity {
    static func update(_ state: CompanionAttributes.ContentState) async {
        for activity in Activity<CompanionAttributes>.activities {
            await activity.update(ActivityContent(state: state, staleDate: state.updatedAt.addingTimeInterval(300)))
        }
    }

    static func end() async {
        for activity in Activity<CompanionAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

struct RefreshCompanionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "看看博客状态"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let overview = try await ConnectionStore.overview()
        await CompanionActivity.update(.init(overview: overview, demo: ConnectionStore.load().demo))
        return .result()
    }
}

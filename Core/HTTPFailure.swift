import Foundation

/// Safe UI categories, never arbitrary response text (which may echo secrets).
public struct HTTPFailure: LocalizedError, Sendable, Equatable {
    public let status: Int
    public let category: String

    public init(status: Int, body: Data = Data()) {
        self.status = status
        let json = try? JSONDecoder().decode(JSONValue.self, from: body)
        let raw = json?["error"].string ?? json?["detail"].string ?? json?["message"].string ?? ""
        if status == 409 {
            switch raw {
            case "confirm_already_used": category = "confirm_already_used"
            case "该轮次已被替换，没有继续执行。": category = "turn_replaced"
            case "原始轮次标识不可用，请重新发起请求。": category = "source_turn_unavailable"
            case "历史上下文正在同步，请稍后重试。", "该轮次已丢弃或历史正在同步，请重新发送。": category = "history_sync"
            case "聊天版本已更新，请刷新页面后重试。": category = "stream_version_mismatch"
            default: category = "conflict_unknown"
            }
        } else { category = "http_\(status)" }
    }

    public var errorDescription: String? {
        switch category {
        case "confirm_already_used": return "服务端报告这张确认卡已使用；请核对执行结果，不要重发批准。"
        case "turn_replaced": return "原始轮次已被替换，服务端拒绝继续；请重新读取当前任务状态。"
        case "source_turn_unavailable": return "服务端找不到原始轮次，请核对会话历史。"
        case "history_sync": return "会话历史正在同步，本次请求被拒绝；请稍后核对状态。"
        case "stream_version_mismatch": return "聊天协议版本不匹配，请核对客户端与博客部署版本。"
        case "conflict_unknown": return "服务端返回 409，但冲突原因尚未识别；请用请求编号核对，不能据此判断操作已消费。"
        default:
            if status == 401 { return "登录已失效，请重新登录。" }
            if status == 403 { return "当前账号没有这项权限。" }
            if status == 429 { return "请求过于频繁，请稍后再试。" }
            return "博客请求失败（\(status)）。"
        }
    }
}

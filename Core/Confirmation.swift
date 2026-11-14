import Foundation

public struct Confirmation: Identifiable, Sendable {
    public struct Option: Identifiable, Sendable {
        public let label: String
        public let value: String
        public var id: String { value }
    }
    public let id: String
    public let taskID: String
    public let question: String
    public let token: String
    public let options: [Option]
    public let details: JSONValue
    public let notices: [String]
    public let receivedAt: TimeInterval
    public let remaining: Double
    public let supportsNativeReview: Bool

    public init(_ json: JSONValue) throws {
        guard let id = json["id"].string, !id.isEmpty,
              let task = json["task_id"].string, !task.isEmpty,
              let q = json["q"].string, !q.isEmpty,
              let token = json["token"].string, !token.isEmpty,
              let exp = json["exp"].number, exp.isFinite,
              let serverTime = json["server_time"].number, serverTime.isFinite,
              let opts = json["opts"].array, !opts.isEmpty else { throw AgentError.protocolViolation }
        self.id = id; taskID = task; question = q; self.token = token
        options = try opts.map { item in
            guard let label = item["label"].string, let value = item["value"].string,
                  !label.isEmpty, !value.isEmpty else { throw AgentError.protocolViolation }
            return Option(label: label, value: value)
        }
        guard Set(options.map(\.value)).count == options.count else { throw AgentError.protocolViolation }
        details = json["details"]
        notices = json["notices"].array?.compactMap { $0["text"].string ?? $0.string } ?? []
        remaining = max(0, exp - serverTime)
        receivedAt = ProcessInfo.processInfo.systemUptime
        // Image/cover review and batch selection remain in the blog's existing review UI.
        let fieldsValid = (details["fields"].array ?? []).allSatisfy {
            $0["label"].string != nil && $0["value"].string != nil
        }
        let sectionsValid = (details["sections"].array ?? []).allSatisfy {
            $0["label"].string != nil && $0["text"].string != nil
                && ["plain", "markdown"].contains($0["format"].string ?? "")
        }
        let detailsValid = details == .null || (details.object != nil
            && details["fields"].array != nil && details["sections"].array != nil
            && fieldsValid && sectionsValid)
        supportsNativeReview = json["image_review"] == .null && json["cover_review"] == .null
            && detailsValid && options.allSatisfy { ["yes", "no", "other"].contains($0.value) }
    }

    public var expired: Bool { ProcessInfo.processInfo.systemUptime - receivedAt >= remaining }
}

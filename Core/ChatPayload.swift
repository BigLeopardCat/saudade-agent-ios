import Foundation

public enum ChatPayload {
    public static func message(_ text: String, conversationID: Int, turnID: String) -> JSONValue {
        .object(["message": .string(text), "conversation_id": .number(Double(conversationID)),
                 "turn_id": .string(turnID), "task_id": .string(turnID),
                 "browser_feedback": .bool(false), "task_inputs": .bool(false)])
    }

    public static func approval(_ card: Confirmation, conversationID: Int) -> JSONValue {
        // A new HTTP attempt is not a new semantic turn. The host fills its authoritative
        // original turn_id when omitted; an invented UUID causes turn-replaced HTTP 409.
        .object(["message": .string(""), "conversation_id": .number(Double(conversationID)),
                 "confirm_token": .string(card.token), "browser_feedback": .bool(false),
                 "task_inputs": .bool(false)])
    }
}

/// A failed stream never discards a card or makes an uncertain approval replayable.
public struct ConfirmationReviewState: Sendable {
    public private(set) var card: Confirmation?
    public private(set) var requiresRefresh = false

    public init() {}
    public mutating func receive(_ card: Confirmation) { self.card = card; requiresRefresh = false }
    public mutating func clear() { card = nil; requiresRefresh = false }
    public mutating func interrupt() { if card != nil { requiresRefresh = true } }
    public mutating func beginApproval() { requiresRefresh = true }
    public mutating func finishApproval(_ submitted: Confirmation) {
        if card?.id == submitted.id && card?.token == submitted.token { clear() }
    }
    public func canApprove(_ candidate: Confirmation) -> Bool {
        !requiresRefresh && candidate.id == card?.id && candidate.taskID == card?.taskID
            && candidate.token == card?.token && !candidate.expired && candidate.supportsNativeReview
    }
}

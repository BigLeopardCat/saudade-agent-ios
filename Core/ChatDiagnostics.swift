import Foundation

public enum ChatCancellationSource: String, Codable, Sendable {
    case userStop = "user_stop"
    case parentTask = "parent_task"
    case consumerCancelled = "consumer_cancelled"
    case consumerEnded = "consumer_ended"
    case ownerReleased = "owner_released"
}

/// The allowlist is intentional: no error descriptions, userInfo, headers, URLs or payloads.
public struct ChatDiagnosticRecord: Codable, Sendable {
    public var schemaVersion = 1
    public var timestamp: Date
    public var requestID: String
    public var serverRequestID: String?
    public var buildCommit: String
    public var conversationID: Int?
    public var taskID: String?
    public var phase: String
    public var scene: String
    public var chatVisible: Bool
    public var elapsedMS: Int
    public var httpStatus: Int?
    public var cancellationSource: ChatCancellationSource?
    public var failureKind: String?
    public var nsErrorDomain: String?
    public var nsErrorCode: Int?
    public var lastEvent: String?
    public var eventCount: Int
    public var ignoredExtensionCount: Int
    public var receivedDone: Bool
}

public final class ChatTrace: @unchecked Sendable {
    public let requestID: String
    private let lock = NSLock()
    private let started = ProcessInfo.processInfo.systemUptime
    private let sink: @Sendable (ChatDiagnosticRecord) -> Void
    private var record: ChatDiagnosticRecord
    private var finished = false
    private var receivedError = false

    public init(requestID: String = UUID().uuidString, buildCommit: String = "unversioned",
                sink: @escaping @Sendable (ChatDiagnosticRecord) -> Void = { _ in }) {
        self.requestID = requestID
        self.sink = sink
        record = ChatDiagnosticRecord(timestamp: Date(), requestID: requestID,
            buildCommit: buildCommit, phase: "created", scene: "unknown", chatVisible: false,
            elapsedMS: 0, eventCount: 0, ignoredExtensionCount: 0, receivedDone: false)
    }

    public var snapshot: ChatDiagnosticRecord {
        lock.lock(); defer { lock.unlock() }
        return record
    }

    private func change(_ action: (inout ChatDiagnosticRecord) -> Void, emit: Bool) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        action(&record)
        record.timestamp = Date()
        record.elapsedMS = max(0, Int((ProcessInfo.processInfo.systemUptime - started) * 1000))
        let copy = record
        lock.unlock()
        if emit { sink(copy) }
    }

    public func startedRequest(conversationID: Int?, taskID: String?) {
        let safeTask = taskID.flatMap { value -> String? in
            guard !value.isEmpty, value.utf8.count <= 100,
                  value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
            return value
        }
        change({ $0.phase = "request_started"; $0.conversationID = conversationID; $0.taskID = safeTask }, emit: true)
    }

    public func response(status: Int, serverRequestID: String?) {
        let safeID = serverRequestID.flatMap { value -> String? in
            guard !value.isEmpty, value.utf8.count <= 100,
                  value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
            return value
        }
        change({ $0.phase = "response_headers"; $0.httpStatus = status; $0.serverRequestID = safeID }, emit: true)
    }

    public func event(_ name: String) {
        let known = ["text", "error", "progress", "done", "text_reset", "confirmation", "command", "task_input", "pending", "receipts"]
        let safeName = known.contains(name) ? name : "extension"
        lock.lock()
        if name == "error" { receivedError = true }
        lock.unlock()
        change({
            $0.phase = "event"
            $0.lastEvent = safeName
            $0.eventCount += 1
            if safeName == "extension" { $0.ignoredExtensionCount += 1 }
            if safeName == "done" { $0.receivedDone = true }
        }, emit: ["error", "confirmation", "done"].contains(name))
    }

    public func lifecycle(scene: String, chatVisible: Bool) {
        let safeScene = ["active", "inactive", "background", "unknown"].contains(scene) ? scene : "unknown"
        change({ $0.phase = "lifecycle_observed"; $0.scene = safeScene; $0.chatVisible = chatVisible }, emit: true)
    }

    public func invalidFrame(_ name: String?) {
        let known = ["text", "error", "progress", "done", "text_reset", "confirmation", "command", "task_input", "pending", "receipts"]
        change({ $0.lastEvent = name.flatMap { known.contains($0) ? $0 : "extension" } }, emit: false)
    }

    public func cancel(_ source: ChatCancellationSource) {
        change({
            if $0.cancellationSource == nil { $0.cancellationSource = source }
            $0.phase = "cancel_requested"
        }, emit: true)
    }

    public func finish(error: Error? = nil) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        record.timestamp = Date()
        record.elapsedMS = max(0, Int((ProcessInfo.processInfo.systemUptime - started) * 1000))
        if let error {
            let ns = error as NSError
            record.nsErrorDomain = ns.domain
            record.nsErrorCode = ns.code
            if let http = error as? HTTPFailure { record.failureKind = http.category }
            else if receivedError { record.failureKind = "server_error_event" }
            else if error is CancellationError || (ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled) {
                record.failureKind = record.cancellationSource == nil ? "cancellation_unattributed" : "cancelled"
            } else if ns.domain == NSURLErrorDomain { record.failureKind = "network_error" }
            else { record.failureKind = "protocol_or_application_error" }
            record.phase = "failed"
        } else if record.receivedDone && record.cancellationSource == nil {
            record.phase = "completed"
        } else {
            record.phase = "incomplete"
        }
        let copy = record
        lock.unlock()
        sink(copy)
    }
}

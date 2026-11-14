import Foundation

/// Owns the producer explicitly. Normal finish does not cancel its own producer task.
public final class ManagedChatStream: @unchecked Sendable {
    public let events: AsyncThrowingStream<AgentEvent, Error>
    public let trace: ChatTrace
    private let control: Control

    public init(trace: ChatTrace,
                operation: @escaping @Sendable (@escaping @Sendable (AgentEvent) -> Void) async throws -> Void) {
        self.trace = trace
        let control = Control(trace: trace)
        self.control = control
        let pair = AsyncThrowingStream<AgentEvent, Error>.makeStream()
        events = pair.stream
        pair.continuation.onTermination = { termination in
            if case .cancelled = termination { control.cancel(.consumerCancelled) }
        }
        let task = Task {
            do {
                try Task.checkCancellation()
                try await operation { event in
                    trace.event(event.name)
                    pair.continuation.yield(event)
                }
                try Task.checkCancellation()
                guard trace.snapshot.receivedDone else { throw AgentError.incompleteStream }
                control.complete()
                trace.finish()
                pair.continuation.finish()
            } catch {
                control.complete()
                trace.finish(error: error)
                pair.continuation.finish(throwing: error)
            }
        }
        control.install(task)
    }

    public func cancel(_ source: ChatCancellationSource) { control.cancel(source) }
    deinit { control.cancel(.ownerReleased) }

    private final class Control: @unchecked Sendable {
        let trace: ChatTrace
        let lock = NSLock()
        var task: Task<Void, Never>?
        var cancelled = false
        var completed = false
        init(trace: ChatTrace) { self.trace = trace }
        func install(_ task: Task<Void, Never>) {
            lock.lock()
            if !completed { self.task = task }
            let cancel = cancelled
            lock.unlock()
            if cancel { task.cancel() }
        }
        func cancel(_ source: ChatCancellationSource) {
            lock.lock()
            guard !completed else { lock.unlock(); return }
            cancelled = true
            let task = task
            lock.unlock()
            trace.cancel(source)
            task?.cancel()
        }
        func complete() {
            lock.lock(); completed = true; task = nil; lock.unlock()
        }
    }
}

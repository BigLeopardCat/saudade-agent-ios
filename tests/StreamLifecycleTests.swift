import Foundation
import XCTest
@testable import LingyueCore

final class StreamLifecycleTests: XCTestCase {
    private func connection() throws -> BlogConnection { try .init(origin: "https://\(UUID().uuidString).example.test", token: "TOKEN_CANARY") }
    private func client(_ scenario: Scenario) throws -> BlogClient {
        let connection = try connection()
        MockProtocol.register(scenario, host: connection.origin.host!)
        return BlogClient(connection: connection, streamSessionFactory: {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockProtocol.self]
            config.timeoutIntervalForRequest = 2
            config.timeoutIntervalForResource = 5
            return URLSession(configuration: config)
        })
    }

    func testDoneCompletesWithoutWaitingForEOForCancellingProducer() async throws {
        let scenario = Scenario(wire: "event: text\ndata: \"hello\"\n\nevent: done\ndata: {}\n\n")
        let trace = ChatTrace()
        let handle = try client(scenario).stream(.object([:]), trace: trace)
        var events: [String] = []
        for try await event in handle.events { events.append(event.name) }
        XCTAssertEqual(events, ["text", "done"])
        XCTAssertEqual(trace.snapshot.phase, "completed")
        XCTAssertNil(trace.snapshot.cancellationSource)
        XCTAssertEqual(scenario.count, 1)
        XCTAssertEqual(scenario.header("X-Request-ID"), trace.requestID)
        XCTAssertEqual(scenario.header("X-Agent-Stream-Version"), "2")
    }

    func testExplicitStopPropagatesToURLSessionAndPreservesSource() async throws {
        let first = expectation(description: "first frame")
        let stopped = expectation(description: "URL loading cancelled")
        let scenario = Scenario(wire: "event: text\ndata: \"partial\"\n\n", onStop: { stopped.fulfill() })
        let trace = ChatTrace()
        let handle = try client(scenario).stream(.object([:]), trace: trace)
        let consumer = Task {
            do { for try await _ in handle.events { first.fulfill() } } catch { }
        }
        await fulfillment(of: [first], timeout: 3)
        handle.cancel(.userStop)
        consumer.cancel()
        await fulfillment(of: [stopped], timeout: 3)
        await consumer.value
        // Consumer cancellation may return before the producer writes its final diagnostic.
        await eventually { trace.snapshot.phase == "failed" }
        XCTAssertEqual(trace.snapshot.cancellationSource, .userStop)
        XCTAssertFalse(trace.snapshot.receivedDone)
        XCTAssertEqual(scenario.count, 1)
    }

    func testParentConsumerCancellationStopsNetwork() async throws {
        let first = expectation(description: "frame")
        let stopped = expectation(description: "network cancelled")
        let scenario = Scenario(wire: "event: progress\ndata: \"working\"\n\n", onStop: { stopped.fulfill() })
        let trace = ChatTrace()
        let handle = try client(scenario).stream(.object([:]), trace: trace)
        let consumer = Task {
            do { for try await _ in handle.events { first.fulfill() } } catch { }
        }
        await fulfillment(of: [first], timeout: 3)
        consumer.cancel()
        await fulfillment(of: [stopped], timeout: 3)
        await consumer.value
        await eventually { trace.snapshot.phase == "failed" }
        XCTAssertEqual(trace.snapshot.cancellationSource, .consumerCancelled)
        XCTAssertEqual(scenario.count, 1)
    }

    func testKnownParseFailureClosesNetworkAndRetainsPriorConfirmation() async throws {
        let stopped = expectation(description: "parse failure closes HTTP")
        let wire = "event: confirmation\ndata: {\"id\":\"c\",\"task_id\":\"t\",\"q\":\"review\",\"token\":\"CONFIRM_CANARY\",\"exp\":400,\"server_time\":100,\"opts\":[{\"label\":\"yes\",\"value\":\"yes\"}]}\n\nevent: progress\ndata: {\"text\":\"invalid\"}\n\n"
        let scenario = Scenario(wire: wire, onStop: { stopped.fulfill() })
        let trace = ChatTrace()
        let handle = try client(scenario).stream(.object([:]), trace: trace)
        var state = ConfirmationReviewState()
        do {
            for try await event in handle.events {
                if event.name == "confirmation" { state.receive(try Confirmation(event.data)) }
            }
            XCTFail("Known malformed progress must fail")
        } catch { state.interrupt() }
        await fulfillment(of: [stopped], timeout: 3)
        XCTAssertEqual(state.card?.id, "c")
        XCTAssertTrue(state.requiresRefresh)
        XCTAssertFalse(trace.snapshot.receivedDone)
        XCTAssertEqual(trace.snapshot.phase, "failed")
        XCTAssertEqual(trace.snapshot.lastEvent, "progress")
        XCTAssertEqual(scenario.count, 1)
    }

    func testNetworkNSErrorIsPreservedWithoutDescriptionsOrSecrets() async throws {
        let secret = "PRIVATE_DESCRIPTION_TOKEN_BODY_CANARY"
        let original = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost,
                               userInfo: [NSLocalizedDescriptionKey: secret, NSURLErrorFailingURLStringErrorKey: "https://example.test/?token=\(secret)"])
        let scenario = Scenario(wire: "", failure: original)
        let trace = ChatTrace()
        let handle = try client(scenario).stream(.object([:]), trace: trace)
        do { for try await _ in handle.events {}; XCTFail("Expected network error") } catch { }
        let snapshot = trace.snapshot
        XCTAssertEqual(snapshot.nsErrorDomain, NSURLErrorDomain)
        XCTAssertEqual(snapshot.nsErrorCode, NSURLErrorNetworkConnectionLost)
        XCTAssertNil(snapshot.cancellationSource)
        XCTAssertFalse(snapshot.receivedDone)
        let log = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(log.contains(secret)); XCTAssertFalse(log.contains("TOKEN_CANARY"))
        XCTAssertEqual(scenario.count, 1)
    }

    func testHTTP409IsClassifiedAndNeverReplayed() async throws {
        let scenario = Scenario(wire: "{\"error\":\"该轮次已被替换，没有继续执行。\"}", status: 409, finishes: true)
        let trace = ChatTrace()
        let handle = try client(scenario).stream(.object([:]), trace: trace)
        do { for try await _ in handle.events {}; XCTFail("Expected 409") }
        catch let error as HTTPFailure { XCTAssertEqual(error.category, "turn_replaced") }
        catch { XCTFail("Unexpected error type: \(type(of: error))") }
        XCTAssertEqual(trace.snapshot.httpStatus, 409)
        XCTAssertEqual(trace.snapshot.failureKind, "turn_replaced")
        XCTAssertEqual(scenario.count, 1)
    }

    func testServerErrorEventIsNotSwallowedOrTurnedIntoDone() async throws {
        let scenario = Scenario(wire: "event: error\ndata: \"safe user error\"\n\n")
        let trace = ChatTrace()
        let handle = try client(scenario).stream(.object([:]), trace: trace)
        var received: [String] = []
        do { for try await event in handle.events { received.append(event.name) }; XCTFail("Expected server error") } catch { }
        XCTAssertEqual(received, ["error"])
        XCTAssertFalse(trace.snapshot.receivedDone)
        XCTAssertEqual(trace.snapshot.failureKind, "server_error_event")
        XCTAssertEqual(scenario.count, 1)
    }

    func testEOFWithoutDoneFails() async throws {
        let scenario = Scenario(wire: "event: text\ndata: \"partial\"\n\n", finishes: true)
        let trace = ChatTrace()
        let handle = try client(scenario).stream(.object([:]), trace: trace)
        do { for try await _ in handle.events {}; XCTFail("Missing done must fail") }
        catch { XCTAssertEqual(error as? AgentError, .incompleteStream) }
        XCTAssertFalse(trace.snapshot.receivedDone)
    }

    func testSceneAndViewChangesObserveButDoNotCancel() async throws {
        let ready = expectation(description: "producer started")
        let trace = ChatTrace()
        let handle = ManagedChatStream(trace: trace) { emit in
            ready.fulfill()
            try await Task.sleep(for: .milliseconds(150))
            try emit(.init(name: "done", data: .object([:])))
        }
        await fulfillment(of: [ready], timeout: 2)
        trace.lifecycle(scene: "background", chatVisible: false)
        trace.lifecycle(scene: "active", chatVisible: true)
        for try await _ in handle.events { }
        XCTAssertNil(trace.snapshot.cancellationSource)
        XCTAssertEqual(trace.snapshot.phase, "completed")
    }

    func testOwnerReleaseCancelsItsProducer() async throws {
        let ready = expectation(description: "started")
        let cancelled = expectation(description: "producer cancelled")
        let trace = ChatTrace()
        var handle: ManagedChatStream? = ManagedChatStream(trace: trace) { _ in
            ready.fulfill()
            do { try await Task.sleep(for: .seconds(30)) }
            catch { cancelled.fulfill(); throw error }
        }
        XCTAssertNotNil(handle)
        await fulfillment(of: [ready], timeout: 2)
        handle = nil
        await fulfillment(of: [cancelled], timeout: 2)
        await eventually { trace.snapshot.phase == "failed" }
        XCTAssertEqual(trace.snapshot.cancellationSource, .ownerReleased)
    }

    func testSlowConsumerFailsExplicitlyAtBufferLimitWithoutFakeDone() async throws {
        let trace = ChatTrace()
        let finished = expectation(description: "producer bounded")
        let handle = ManagedChatStream(trace: trace) { emit in
            defer { finished.fulfill() }
            for _ in 0..<1000 { try emit(.init(name: "text", data: .string("chunk"))) }
            try emit(.init(name: "done", data: .object([:])))
        }
        await fulfillment(of: [finished], timeout: 2)
        var count = 0
        do { for try await _ in handle.events { count += 1 }; XCTFail("Overflow must fail") }
        catch { XCTAssertEqual(error as? AgentError, .frameTooLarge) }
        XCTAssertEqual(count, 256)
        XCTAssertFalse(trace.snapshot.receivedDone)
    }

    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Producer did not reach its expected terminal state")
    }
}

private final class Scenario: @unchecked Sendable {
    let wire: String
    let status: Int
    let finishes: Bool
    let failure: Error?
    let onStop: @Sendable () -> Void
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0
    private var request: URLRequest?
    init(wire: String, status: Int = 200, finishes: Bool = false, failure: Error? = nil,
         onStop: @escaping @Sendable () -> Void = {}) {
        self.wire = wire; self.status = status; self.finishes = finishes; self.failure = failure; self.onStop = onStop
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return starts }
    func header(_ name: String) -> String? { lock.lock(); defer { lock.unlock() }; return request?.value(forHTTPHeaderField: name) }
    func start(_ loading: MockProtocol) {
        lock.lock(); starts += 1; request = loading.request; lock.unlock()
        if let failure { loading.client?.urlProtocol(loading, didFailWithError: failure); return }
        let response = HTTPURLResponse(url: loading.request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": status == 200 ? "text/event-stream" : "application/json"])!
        loading.client?.urlProtocol(loading, didReceive: response, cacheStoragePolicy: .notAllowed)
        loading.client?.urlProtocol(loading, didLoad: Data(wire.utf8))
        if finishes { loading.client?.urlProtocolDidFinishLoading(loading) }
    }
    func stop() {
        lock.lock(); stops += 1; let first = stops == 1; lock.unlock()
        if first { onStop() }
    }
}

private final class MockProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var scenarios: [String: Scenario] = [:]
    static func register(_ scenario: Scenario, host: String) { lock.lock(); scenarios[host] = scenario; lock.unlock() }
    private var scenario: Scenario? {
        Self.lock.lock(); defer { Self.lock.unlock() }
        return Self.scenarios[request.url!.host!]
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".example.test") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { scenario?.start(self) }
    override func stopLoading() { scenario?.stop() }
}

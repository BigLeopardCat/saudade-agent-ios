import Foundation
import LingyueCore
import OSLog

enum BuildInfo {
    static var commit: String { Bundle.main.object(forInfoDictionaryKey: "BuildSourceCommit") as? String ?? "unversioned" }
    static var label: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build)) · \(commit.prefix(12))"
    }
}

/// A bounded, local metadata-only diagnostic file, exported only by the user.
final class ChatLogStore: @unchecked Sendable {
    static let shared = ChatLogStore()
    private let lock = NSLock()
    private let logger = Logger(subsystem: "site.saudade.lingyue", category: "ChatStream")
    let fileURL: URL

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("chat-stream.jsonl")
        if !FileManager.default.fileExists(atPath: fileURL.path) { try? Data().write(to: fileURL) }
    }

    func append(_ record: ChatDiagnosticRecord) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(record), let line = String(data: data, encoding: .utf8) else { return }
        logger.info("\(line, privacy: .public)")
        lock.lock(); defer { lock.unlock() }
        let old = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let lines = Array(old.split(separator: "\n").suffix(199)).map(String.init) + [line]
        try? (lines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

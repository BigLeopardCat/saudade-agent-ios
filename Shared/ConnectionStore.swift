import Foundation
import Security
import LingyueCore

enum ConnectionStore {
    struct Configuration: Codable, Equatable {
        var demo = true
        var origin = "https://saudade.site"
    }
    static func load() -> Configuration {
        guard let data = UserDefaults.standard.data(forKey: "lingyue.connection"),
              let config = try? JSONDecoder().decode(Configuration.self, from: data) else { return .init() }
        return config
    }
    static func save(_ config: Configuration) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(config), forKey: "lingyue.connection")
    }
    private static func query(_ origin: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "site.saudade.lingyue.login",
         kSecAttrAccount as String: origin]
    }
    static func token(for origin: String) -> String {
        var q = query(origin)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func setToken(_ token: String, origin: String) throws {
        let q = query(origin)
        guard !token.isEmpty else {
            let status = SecItemDelete(q as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AgentError.message("无法删除本机登录凭据。") }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let updated = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw AgentError.message("无法更新登录凭据，请重试。") }
        var value = q
        value.merge(attributes) { _, new in new }
        guard SecItemAdd(value as CFDictionary, nil) == errSecSuccess else {
            throw AgentError.message("无法保存登录凭据，请重试。")
        }
    }
    static func client(_ configuration: Configuration? = nil) throws -> BlogClient {
        let config = configuration ?? load()
        return BlogClient(connection: try BlogConnection(origin: config.origin, token: token(for: config.origin)))
    }
    static func overview() async throws -> Overview {
        let config = load()
        return config.demo ? .demo : await Overview.load(client: try client(config))
    }
}

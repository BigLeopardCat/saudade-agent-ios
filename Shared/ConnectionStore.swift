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
        SecItemDelete(q as CFDictionary)
        guard !token.isEmpty else { return }
        var value = q
        value[kSecValueData as String] = Data(token.utf8)
        value[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
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

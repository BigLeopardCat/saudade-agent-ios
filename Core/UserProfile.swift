import Foundation

public struct UserProfile: Sendable, Equatable {
    public let username: String
    public let nickname: String
    public let avatar: String?
    public let role: String
    public var displayName: String { nickname.isEmpty ? username : nickname }
    public var canManage: Bool { ["admin", "superadmin"].contains(role) }

    public init(_ response: JSONValue) throws {
        let data = response["data"]
        guard let username = data["username"].string, !username.isEmpty,
              let nickname = data["nickname"].string, let role = data["role"].string else { throw AgentError.invalidResponse }
        self.username = String(username.prefix(100)); self.nickname = String(nickname.prefix(100))
        avatar = data["avatar"].string; self.role = role
    }

    /// Avatars are anonymous, same-origin HTTPS images. Never follow arbitrary credentialed URLs.
    public func avatarURL(origin: URL) -> URL? {
        guard let avatar, avatar.utf8.count <= 2048,
              let url = URL(string: avatar, relativeTo: origin)?.absoluteURL,
              url.scheme == "https", url.host == origin.host, url.port == origin.port,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
    }
}

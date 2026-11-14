import ImageIO
import LingyueCore
import SwiftUI
import UIKit

private final class AvatarRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

private actor AvatarImages {
    static let shared = AvatarImages()
    private let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>(); cache.countLimit = 16; cache.totalCostLimit = 2_097_152; return cache
    }()
    private var loading: [URL: Task<UIImage, Error>] = [:]
    func image(_ url: URL) async throws -> UIImage {
        if let image = cache.object(forKey: url as NSURL) { return image }
        if let task = loading[url] { return try await task.value }
        guard loading.count < 4 else { throw AgentError.frameTooLarge }
        let task = Task { try await Self.fetch(url) }
        loading[url] = task
        defer { loading[url] = nil }
        let image = try await task.value
        cache.setObject(image, forKey: url as NSURL, cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
        return image
    }
    private static func fetch(_ url: URL) async throws -> UIImage {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 20
        config.httpCookieStorage = nil; config.urlCache = nil; config.urlCredentialStorage = nil
        let session = URLSession(configuration: config, delegate: AvatarRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              ["image/png", "image/jpeg", "image/webp", "image/heic"].contains(response.mimeType ?? ""),
              response.expectedContentLength <= 1_048_576 else { throw AgentError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 1_048_576 else { throw AgentError.frameTooLarge }
            data.append(byte)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 144,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw AgentError.invalidResponse }
        let image = UIImage(cgImage: cg)
        return image
    }
}

struct IdentityAvatar: View {
    let profile: UserProfile?
    let origin: String
    var size: CGFloat = 32
    @State private var image: UIImage?
    private var url: URL? { URL(string: origin).flatMap { profile?.avatarURL(origin: $0) } }
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else {
                ZStack {
                    Color.purple.opacity(0.12)
                    Text(String((profile?.displayName ?? "我").prefix(1))).font(.system(size: size * 0.42, weight: .semibold))
                }
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .accessibilityLabel(profile?.displayName ?? "用户头像")
        .task(id: url) {
            image = nil
            guard let url else { return }
            do { let value = try await AvatarImages.shared.image(url); try Task.checkCancellation(); image = value }
            catch { /* A local initial is the image failure state; credentials are never sent. */ }
        }
    }
}

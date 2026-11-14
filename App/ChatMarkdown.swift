import ImageIO
import LingyueCore
import MarkdownUI
import SwiftUI
import UIKit

private enum LocalStickerImages {
    static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>(); cache.countLimit = 24; cache.totalCostLimit = 7_000_000; return cache
    }()
    static func image(_ url: URL?) -> UIImage? {
        guard let file = StickerCatalog.file(for: url) else { return nil }
        if let image = cache.object(forKey: file as NSString) { return image }
        guard let resource = Bundle.main.url(forResource: (file as NSString).deletingPathExtension, withExtension: "webp"),
              let source = CGImageSourceCreateWithURL(resource as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 256
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg, scale: 2, orientation: .up)
        cache.setObject(image, forKey: file as NSString, cost: cg.bytesPerRow * cg.height)
        return image
    }
}

private struct StickerImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        if let image = LocalStickerImages.image(url) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 128, maxHeight: 128)
        } else {
            Label("外部图片未加载", systemImage: "photo").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct StickerInlineProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        guard let image = LocalStickerImages.image(url) else { throw AgentError.invalidResponse }
        return Image(uiImage: image)
    }
}

struct ChatMarkdown: View, Equatable {
    let text: String
    var body: some View {
        Markdown(StickerCatalog.markdown(text.isEmpty ? "…" : text))
            .markdownImageProvider(StickerImageProvider())
            .markdownInlineImageProvider(StickerInlineProvider())
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "https", url.user == nil, url.password == nil else { return .discarded }
                return .systemAction
            })
    }
}

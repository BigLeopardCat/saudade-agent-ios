import Foundation
import ImageIO

func image(_ path: String, expected: Int, opaque: Bool = false) throws {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          properties[kCGImagePropertyPixelWidth] as? Int == expected,
          properties[kCGImagePropertyPixelHeight] as? Int == expected,
          CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { fatalError("Invalid bundled image: \(path)") }
    if opaque { precondition(properties[kCGImagePropertyHasAlpha] as? Bool != true, "AppIcon must be opaque") }
    else { precondition(properties[kCGImagePropertyHasAlpha] as? Bool == true, "Avatar/sticker must retain alpha") }
}
try image("App/Assets.xcassets/AppIcon.appiconset/AppIcon.png", expected: 1024, opaque: true)
try image("Resources/Assets.xcassets/LingyueAvatar.imageset/lingyue-head.png", expected: 384)
let files = try FileManager.default.contentsOfDirectory(atPath: "App/Stickers").filter { $0.hasSuffix(".webp") }
precondition(files.count == 24)
for file in files { try image("App/Stickers/" + file, expected: 256) }
print("Validated opaque AppIcon, transparent island head, and 24 decodable local stickers")

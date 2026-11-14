import Foundation
import XCTest
@testable import LingyueCore

final class StickerTests: XCTestCase {
    func testBothBlogAliasFormsUseTheSameBundledImage() {
        let raw = StickerCatalog.markdown("收到 :比心: ![表情](:比心:)")
        XCTAssertEqual(raw.components(separatedBy: "lingyue-sticker://builtin/bixin-cardigan.webp").count - 1, 2)
        XCTAssertFalse(raw.contains("![表情](!["))
    }
    func testCodeAndEscapesRemainLiteral() {
        for source in ["`:比心:`", "``:比心:``", "```markdown\n:比心:\n```", "~~~\n![x](:比心:)\n~~~", "    :比心:", "\t:比心:", #"\:比心:"#] {
            XCTAssertEqual(StickerCatalog.markdown(source), source)
        }
    }
    func testUnknownAliasesAndOrdinaryImageOrLinkTargetsArePreserved() {
        let source = ":不存在的: ![x](https://example.test/:比心:) [链接](https://example.test/:比心:) <https://example.test/:比心:>"
        XCTAssertEqual(StickerCatalog.markdown(source), source)
    }
    func testCatalogueExpandsAll24Stickers() {
        let result = StickerCatalog.markdown(":全部表情:")
        XCTAssertEqual(result.components(separatedBy: "lingyue-sticker://builtin/").count - 1, 24)
        XCTAssertEqual(Set(StickerCatalog.entries.map(\.file)).count, 24)
    }
    func testOnlyKnownLocalFilesCanBeDecodedAndNoExternalImageIsFetched() {
        XCTAssertEqual(StickerCatalog.file(for: URL(string: "lingyue-sticker://builtin/bixin-cardigan.webp")), "bixin-cardigan.webp")
        XCTAssertNil(StickerCatalog.file(for: URL(string: "https://external.test/tracker.png")))
        XCTAssertNil(StickerCatalog.file(for: URL(string: "file:///private/bixin-cardigan.webp")))
        XCTAssertNil(StickerCatalog.file(for: URL(string: "lingyue-sticker://builtin/bixin-cardigan.webp?token=CANARY")))
    }
}

import Foundation

public enum StickerCatalog {
    public static let entries: [(name: String, file: String)] = [
        ("头疼", "touteng-cardigan"), ("委屈", "weiqu-hoodie"), ("害羞", "haixiu-cardigan"), ("比耶", "biye-cardigan"),
        ("犯错", "fancuo-jacket"), ("生气", "shengqi-jacket"), ("贴贴", "tietie-hoodie"), ("震惊", "zhenjing-jacket"),
        ("困困", "kunkun-hoodie"), ("躺平", "tangping-hoodie"), ("嫌弃", "xianqi-jacket"), ("比心", "bixin-cardigan"),
        ("期待", "qidai-hoodie"), ("疑惑", "yihuo-hoodie"), ("喝茶", "hecha-hoodie"), ("晚安", "wanan-hoodie"),
        ("收到", "shoudao-cardigan"), ("思考", "sikao-cardigan"), ("加油", "jiayou-cardigan"), ("早安", "zaoan-cardigan"),
        ("得意", "deyi-jacket"), ("略略", "luelue-jacket"), ("偷笑", "touxiao-jacket"), ("无语", "wuyu-jacket")
    ]
    public static func file(for url: URL?) -> String? {
        guard let url, url.query == nil, url.fragment == nil else { return nil }
        let file = url.lastPathComponent
        guard entries.contains(where: { $0.file + ".webp" == file }) else { return nil }
        if url.scheme == "lingyue-sticker", url.host == "builtin", url.path == "/" + file { return file }
        if url.path == "/stickers/v2/" + file { return file }
        return nil
    }
    private static func image(_ name: String) -> String? {
        let matches = name == "全部表情" ? entries : entries.filter { $0.name == name }
        guard !matches.isEmpty else { return nil }
        return matches.map { "![\($0.name)](lingyue-sticker://builtin/\($0.file).webp)" }.joined(separator: " ")
    }

    /// Expand the blog's aliases, preserving code, escapes and ordinary link destinations.
    public static func markdown(_ source: String) -> String {
        var fence: (Character, Int)?
        return source.components(separatedBy: "\n").map { line in
            let indentation = line.prefix { $0 == " " }.count
            let trimmed = line.dropFirst(min(indentation, 3))
            let marker = trimmed.first
            let count = trimmed.prefix { $0 == marker }.count
            if let current = fence {
                if indentation <= 3, marker == current.0, count >= current.1,
                   trimmed.dropFirst(count).allSatisfy({ $0.isWhitespace }) { fence = nil }
                return line
            }
            if indentation <= 3, (marker == "`" || marker == "~"), count >= 3 { fence = (marker!, count); return line }
            if indentation >= 4 || line.hasPrefix("\t") { return line }
            return inline(line)
        }.joined(separator: "\n")
    }
    private static func inline(_ source: String) -> String {
        var output = ""
        var cursor = source.startIndex
        while cursor < source.endIndex {
            let next = source.index(after: cursor)
            let character = source[cursor]
            if character == "\\", next < source.endIndex {
                let end = source.index(after: next); output += source[cursor..<end]; cursor = end; continue
            }
            if character == "`" {
                var end = next
                while end < source.endIndex, source[end] == "`" { end = source.index(after: end) }
                let marker = String(source[cursor..<end])
                if let close = source.range(of: marker, range: end..<source.endIndex) {
                    output += source[cursor..<close.upperBound]; cursor = close.upperBound; continue
                }
                output += source[cursor...]; break
            }
            if character == "<", let close = source[next...].firstIndex(of: ">") {
                let end = source.index(after: close); output += source[cursor..<end]; cursor = end; continue
            }
            if character == "[" || (character == "!" && next < source.endIndex && source[next] == "[") {
                if let open = source.range(of: "](", range: next..<source.endIndex),
                   let close = source[open.upperBound...].firstIndex(of: ")") {
                    let target = String(source[open.upperBound..<close])
                    let end = source.index(after: close)
                    if character == "!", target.hasPrefix(":"), target.hasSuffix(":"),
                       let replacement = image(String(target.dropFirst().dropLast())) { output += replacement }
                    else { output += source[cursor..<end] }
                    cursor = end; continue
                }
            }
            if character == ":", let close = source[next...].firstIndex(of: ":"),
               source.distance(from: next, to: close) <= 12,
               let replacement = image(String(source[next..<close])) {
                output += replacement; cursor = source.index(after: close); continue
            }
            output.append(character); cursor = next
        }
        return output
    }
}

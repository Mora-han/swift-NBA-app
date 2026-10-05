import Foundation

// MARK: - 帖子 / 新闻正文

/// 正文页是 Next.js SSR 页面（https://m.hupu.com/bbs/{tid}.html），
/// 完整数据以 JSON 形式内嵌在 `<script id="__NEXT_DATA__">` 里，
/// 所以这里解码的是那份 JSON，而不是去解析 HTML。
public struct ThreadPageRoot: Decodable, Sendable {
    public let props: ThreadPagePropsBox?

    public var pageProps: ThreadPageProps? { props?.pageProps }

    /// 正文与亮评挂在不同分支（t_detail / initialRepliesData），在这里合并
    public var page: ThreadPage? {
        guard let detail = pageProps?.threadInfo?.t_detail else { return nil }
        return ThreadPage(detail: detail,
                          lightReplies: pageProps?.initialRepliesData?.lightReplies ?? [])
    }
}

/// 正文页数据：正文 + 亮评（高赞回复）
public struct ThreadPage: Sendable {
    public let detail: ThreadDetail
    public let lightReplies: [ThreadReply]
}

public struct ThreadPagePropsBox: Decodable, Sendable {
    public let pageProps: ThreadPageProps?
}

public struct ThreadPageProps: Decodable, Sendable {
    public let threadInfo: ThreadInfoBox?
    public let initialRepliesData: ThreadRepliesData?
}

public struct ThreadInfoBox: Decodable, Sendable {
    public let t_detail: ThreadDetail?
}

public struct ThreadDetail: Decodable, Sendable {
    public let tid: FlexString?
    public let title: String?
    /// 正文 HTML（`<p>` / `<img>` / `<br>` / `<span>`），用 ThreadContentParser 转成块
    public let content: String?
    // 计数型字段线上类型不统一（同一帖里 hits 可能是字符串），统一用 FlexString 接
    public let hits: FlexString?
    public let replies: FlexString?
    public let lights: FlexString?
    public let f_info: ThreadForumInfo?
    public let user: ThreadUser?

    public var hitsCount: Int? { hits?.intValue }
    public var repliesCount: Int? { replies?.intValue }
    public var lightsCount: Int? { lights?.intValue }

    /// 已解析的正文块（文字段 + 图片，保持原始顺序）
    public var blocks: [ThreadBlock] { ThreadContentParser.parse(content) }
}

public struct ThreadForumInfo: Decodable, Sendable {
    public let fid: FlexString?
    public let f_name: String?
}

public struct ThreadUser: Decodable, Sendable {
    public let puid: FlexString?
    public let username: String?
    public let header: String?
}

public struct ThreadRepliesData: Decodable, Sendable {
    public let lightReplies: [ThreadReply]?
}

/// 亮评（高赞回复）
public struct ThreadReply: Decodable, Sendable, Identifiable {
    public let pid: FlexString?
    public let content: String?      // 同样是 HTML
    public let light: FlexString?
    public let createDt: String?
    public let location: String?
    public let user: ThreadUser?

    public var lightCount: Int? { light?.intValue }

    public var id: String { pid?.raw ?? "\(user?.username ?? "")-\(content?.prefix(24) ?? "")" }

    /// 回复只展示纯文字，图片/表情直接丢掉
    public var plainText: String {
        ThreadContentParser.plainText(content)
    }
}

// MARK: - 正文块解析

public enum ThreadBlock: Hashable, Sendable {
    case text(String)
    case image(String)   // 已规范为 https
}

/// 把虎扑正文 HTML 拆成可原生渲染的块。
///
/// 正文 HTML 的实际形态很窄：`<p>` 段落、`<div data-hupu-node="image"><p><img src=…>` 配图、
/// `<br>` 换行、`<span>来源：…</span>`、少量 `<video>`。
/// 不需要完整 HTML 解析器，按标签扫描保序转换即可。
public enum ThreadContentParser {
    public static func parse(_ html: String?) -> [ThreadBlock] {
        guard let html, !html.isEmpty else { return [] }

        var blocks: [ThreadBlock] = []
        var buffer = ""
        var index = html.startIndex

        func flushText() {
            for line in buffer.split(separator: "\n", omittingEmptySubsequences: true) {
                let text = decodedEntities(String(line))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                blocks.append(.text(text))
            }
            buffer = ""
        }

        while index < html.endIndex {
            guard html[index] == "<" else {
                buffer.append(html[index])
                index = html.index(after: index)
                continue
            }
            guard let close = html[index...].firstIndex(of: ">") else { break }
            let tag = String(html[html.index(after: index)..<close])
            let name = tag.lowercased()

            if name.hasPrefix("img") || name.hasPrefix("video") {
                if let src = attribute("src", in: tag) ?? attribute("poster", in: tag),
                   !src.isEmpty {
                    flushText()
                    blocks.append(.image(src))
                }
            } else if name.hasPrefix("br") {
                buffer.append("\n")
            } else if name.hasPrefix("/p") || name.hasPrefix("/div") || name.hasPrefix("/h") {
                buffer.append("\n")
            }
            index = html.index(after: close)
        }
        flushText()
        return blocks
    }

    /// 去掉全部标签只留文字（亮评、摘要用）
    public static func plainText(_ html: String?) -> String {
        parse(html).compactMap { block in
            if case .text(let text) = block { return text }
            return nil
        }.joined(separator: " ")
    }

    // MARK: 内部工具

    /// 只取指定属性，避免把 `data-src` / `srcset` 误当成 `src`
    static func attribute(_ name: String, in tag: String) -> String? {
        var searchStart = tag.startIndex
        while let range = tag.range(of: name, options: .caseInsensitive,
                                    range: searchStart..<tag.endIndex) {
            defer { searchStart = range.upperBound }

            let boundaryOK = range.lowerBound == tag.startIndex
                || !(tag[tag.index(before: range.lowerBound)].isLetter
                     || tag[tag.index(before: range.lowerBound)].isNumber)
            var cursor = range.upperBound
            while cursor < tag.endIndex, tag[cursor] == " " { cursor = tag.index(after: cursor) }
            guard boundaryOK, cursor < tag.endIndex, tag[cursor] == "=" else { continue }

            cursor = tag.index(after: cursor)
            while cursor < tag.endIndex, tag[cursor] == " " { cursor = tag.index(after: cursor) }
            guard cursor < tag.endIndex else { return nil }

            let quote = tag[cursor]
            if quote == "\"" || quote == "'" {
                let start = tag.index(after: cursor)
                guard let end = tag[start...].firstIndex(of: quote) else { return nil }
                return decodedEntities(String(tag[start..<end]))
            }
            var end = cursor
            while end < tag.endIndex, tag[end] != " ", tag[end] != ">" { end = tag.index(after: end) }
            return decodedEntities(String(tag[cursor..<end]))
        }
        return nil
    }

    static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": " ", "ensp": " ", "emsp": " ",
        "mdash": "—", "ndash": "–", "hellip": "…", "middot": "·",
        "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’", "times": "×",
    ]

    static func decodedEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "&",
                  let semi = text[index...].firstIndex(of: ";"),
                  text.distance(from: index, to: semi) <= 12 else {
                out.append(text[index])
                index = text.index(after: index)
                continue
            }
            let body = String(text[text.index(after: index)..<semi])
            if let replacement = entities[body] {
                out += replacement
            } else if body.hasPrefix("#") {
                let digits = body.dropFirst()
                let value: UInt32? = (digits.hasPrefix("x") || digits.hasPrefix("X"))
                    ? UInt32(digits.dropFirst(), radix: 16)
                    : UInt32(digits)
                if let value, let scalar = Unicode.Scalar(value) {
                    out.unicodeScalars.append(scalar)
                } else {
                    out += "&" + body + ";"
                }
            } else {
                out += "&" + body + ";"
            }
            index = text.index(after: semi)
        }
        return out
    }
}

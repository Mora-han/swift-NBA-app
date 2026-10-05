import Foundation

// MARK: - 新闻（虎扑 NBA 板块）

/// `news/v2/newsList` —— 一次 20 条，`newsId=上一页最后一条 nid` 翻页。
public struct NewsListRoot: Decodable, Sendable {
    public let data: [NewsItem]?
    public let topNewsCount: Int?

    public var items: [NewsItem] { data ?? [] }
}

public struct NewsItem: Decodable, Sendable, Hashable, Identifiable {
    public let nid: FlexString?        // "22978690"（翻页游标）
    public let tid: FlexString?        // 帖子 id，可拼 bbs 链接
    public let type: String?           // "IMG_TEXT" / "LINK"
    public let title: String?
    public let img: String?
    public let replies: Int?
    public let lights: Int?
    public let link: String?           // kanqiu:// / huputiyu:// / https:// 混合
    public let linkType: String?       // null / "CUSTOM"
    public let badge: [NewsBadge]?
    public let publishTime: String?    // "2026-10-05 11:19:44"
    public let addTime: Double?
    public let top: Bool?

    public var id: String { nid?.raw ?? title ?? UUID().uuidString }

    /// 接口返回的 link 混用三种 scheme，统一换算成浏览器能打开的 https 地址：
    /// - `https://...` 直接用
    /// - `kanqiu://bbs/topic/{tid}` 与 `{tid}` → 虎扑帖子网页版
    /// - `huputiyu://webview/openencodeurl?url=<编码后地址>` → 解出内层 url
    public var webURL: URL? {
        if let link {
            if link.hasPrefix("http") {
                // 未编码的内层地址偶发带空白，URL(string:) 会失败，截断后重试
                if let url = URL(string: link) { return url }
                return URL(string: String(link.prefix(while: { !$0.isWhitespace })))
            }
            if link.hasPrefix("huputiyu://"), let inner = innerURL(from: link) {
                return inner
            }
        }
        if let tid = tid?.raw, !tid.isEmpty {
            return URL(string: "https://bbs.hupu.com/\(tid).html")
        }
        return nil
    }

    /// 取 huputiyu 深链里的 url 参数。URLQueryItem.value 已经做过一次解码，
    /// 若内容仍带 %XX（双重编码）再补一次。
    private func innerURL(from link: String) -> URL? {
        guard let components = URLComponents(string: link),
              var value = components.queryItems?.first(where: { $0.name == "url" })?.value,
              !value.isEmpty else { return nil }
        if value.contains("%"), let decoded = value.removingPercentEncoding {
            value = decoded
        }
        return URL(string: value) ?? URL(string: String(value.prefix(while: { !$0.isWhitespace })))
    }
}

public struct NewsBadge: Decodable, Hashable, Sendable {
    public let name: String?    // "置顶"
    public let color: String?   // "ff3f4c"
}

public extension NewsItem {
    /// 服务端固定 "yyyy-MM-dd HH:mm:ss"（北京时间）。
    /// 显式 locale/时区，避免跟随系统设置解析出偏差；DateFormatter 在 Apple 平台可并发读。
    nonisolated(unsafe) private static let publishFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    var publishDate: Date? {
        guard let publishTime, !publishTime.isEmpty else { return nil }
        return Self.publishFormatter.date(from: publishTime)
    }

    /// 是否置顶（服务端用 top 布尔 + badge 名称两种方式表达）
    var isPinned: Bool {
        top == true || badge?.contains { $0.name == "置顶" } == true
    }
}

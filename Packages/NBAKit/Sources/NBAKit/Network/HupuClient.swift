import Foundation

/// 虎扑数据客户端：
/// - 4 种响应信封自动兼容（标准信封 / salary 信封 / 无 result 的平铺 / 顶层数组）
/// - 429/5xx/网络错误指数退避重试（最多 3 次）
/// - 整个「请求 + 解码」在后台 Task 中执行，不占用主线程
/// - 可选 TTL 内存缓存，避免重复拉取大 JSON
public struct HupuClient: Sendable {
    public static let shared = HupuClient()

    private let session: URLSession
    private let cache: APICache

    public init(session: URLSession = .shared, cache: APICache = .shared) {
        self.session = session
        self.cache = cache
    }

    /// 拉取并解码。`ttl` > 0 时命中期内直接返回缓存。
    public func fetch<T: Decodable & Sendable>(
        _ endpoint: HupuEndpoint,
        ttl: TimeInterval? = nil,
        forceRefresh: Bool = false
    ) async throws -> T {
        let key = endpoint.cacheKey
        if let ttl, ttl > 0, !forceRefresh,
           let hit: T = await cache.value(for: key, ttl: ttl) {
            return hit
        }
        let value: T = try await Task.detached(priority: .userInitiated) {
            try await self.perform(endpoint)
        }.value
        if let ttl, ttl > 0 {
            await cache.store(value, for: key, ttl: ttl)
        }
        return value
    }

    // MARK: - 请求执行

    private func perform<T: Decodable & Sendable>(_ endpoint: HupuEndpoint) async throws -> T {
        var components = URLComponents(
            url: endpoint.baseURL.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = endpoint.query
        guard let url = components.url else { throw HupuError.http(-1) }

        var request = URLRequest(url: url)
        request.setValue(HupuConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        var lastError: Error = HupuError.http(-1)
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 200_000_000))
            }
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw HupuError.http(-1) }
                guard http.statusCode == 200 else {
                    if (500...599).contains(http.statusCode) || http.statusCode == 429 {
                        lastError = HupuError.http(http.statusCode)
                        continue
                    }
                    throw HupuError.http(http.statusCode)
                }
                return try Self.decode(T.self, from: data)
            } catch let e as HupuError {
                if case .http = e { lastError = e; continue }
                throw e
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: - 帖子正文（SSR 页面内嵌 JSON）

    /// 拉取新闻/帖子正文。
    ///
    /// basketballapi 没有新闻正文接口（`news/v2/newsDetail` 之类全部 404），
    /// 正文只存在于 SSR 页面里，所以这里取 HTML 再抠出 `__NEXT_DATA__` 的 JSON。
    public func fetchThreadDetail(
        tid: String,
        ttl: TimeInterval? = nil,
        forceRefresh: Bool = false
    ) async throws -> ThreadPage {
        let endpoint = HupuEndpoint.threadPage(tid: tid)
        let key = endpoint.cacheKey
        if let ttl, ttl > 0, !forceRefresh,
           let hit: ThreadPage = await cache.value(for: key, ttl: ttl) {
            return hit
        }
        let value = try await Task.detached(priority: .userInitiated) {
            try await self.performThreadPage(endpoint)
        }.value
        if let ttl, ttl > 0 {
            await cache.store(value, for: key, ttl: ttl)
        }
        return value
    }

    private func performThreadPage(_ endpoint: HupuEndpoint) async throws -> ThreadPage {
        let url = endpoint.baseURL.appendingPathComponent(endpoint.path)
        var request = URLRequest(url: url)
        request.setValue(HupuConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        var lastError: Error = HupuError.http(-1)
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 200_000_000))
            }
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw HupuError.http(-1) }
                guard http.statusCode == 200 else {
                    if (500...599).contains(http.statusCode) || http.statusCode == 429 {
                        lastError = HupuError.http(http.statusCode)
                        continue
                    }
                    throw HupuError.http(http.statusCode)
                }
                return try Self.decodeThreadPage(from: data)
            } catch let e as HupuError {
                if case .http = e { lastError = e; continue }
                throw e
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func decodeThreadPage(from data: Data) throws -> ThreadPage {
        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            throw HupuError.emptyResult
        }
        guard let json = nextDataJSON(from: html) else {
            throw HupuError.decoding("页面里没有 __NEXT_DATA__")
        }
        let root: ThreadPageRoot
        do {
            root = try JSONDecoder().decode(ThreadPageRoot.self, from: Data(json.utf8))
        } catch {
            throw HupuError.decoding(String(describing: error))
        }
        guard let page = root.page else { throw HupuError.emptyResult }
        return page
    }

    /// 抠出 `<script id="__NEXT_DATA__" type="application/json">…</script>` 之间的 JSON
    static func nextDataJSON(from html: String) -> String? {
        guard let marker = html.range(of: "__NEXT_DATA__") else { return nil }
        guard let open = html[marker.upperBound...].firstIndex(of: ">") else { return nil }
        let start = html.index(after: open)
        guard let end = html[start...].range(of: "</script>")?.lowerBound else { return nil }
        let json = html[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return json.isEmpty ? nil : json
    }

    // MARK: - 四种信封兼容解码

    static func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty else { throw HupuError.emptyResult }
        let decoder = JSONDecoder()

        // 1) 标准信封 { errorCode, errorMsg, result, success, status }
        if let envelope = try? decoder.decode(HupuEnvelope<T>.self, from: data) {
            if envelope.success == false {
                throw HupuError.business(envelope.errorMsg ?? envelope.errorCode ?? "业务错误")
            }
            if let result = envelope.result { return result }
        }

        // 2) salary 信封 { status, msg, result, time }
        if let envelope = try? decoder.decode(SalaryEnvelope<T>.self, from: data) {
            if let status = envelope.status, status != 200 {
                throw HupuError.business(envelope.msg ?? "接口错误 \(status)")
            }
            if let result = envelope.result { return result }
        }

        // 3) 信封存在但 result 解析失败 → 给出真实解码错误（不静默吞掉）
        if let shell = try? decoder.decode(ResponseShell.self, from: data),
           shell.result != nil || shell.success != nil {
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw HupuError.decoding(String(describing: error))
            }
        }

        // 4) 平铺结构 / 顶层数组（teamBasicInfo、searchPlayer 等）
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HupuError.decoding(String(describing: error))
        }
    }
}

// MARK: - TTL 内存缓存

public actor APICache {
    public static let shared = APICache()

    private struct Entry {
        let value: any Sendable
        let expiry: Date
    }

    private var storage: [String: Entry] = [:]

    public init() {}

    public func value<T: Sendable>(for key: String, ttl: TimeInterval) async -> T? {
        guard let entry = storage[key], entry.expiry > .now else {
            storage[key] = nil
            return nil
        }
        return entry.value as? T
    }

    public func store<T: Sendable>(_ value: T, for key: String, ttl: TimeInterval) {
        storage[key] = Entry(value: value, expiry: .now.addingTimeInterval(ttl))
    }

    public func clear() { storage.removeAll() }
}

// MARK: - 图片地址与字符串工具

public enum HupuMedia {
    /// 队徽/球员图存在 http:// 明文地址，统一升级为 https 再交给 AsyncImage
    public static func imageURL(_ string: String?) -> URL? {
        guard var s = string, !s.isEmpty else { return nil }
        if s.hasPrefix("http://") { s.replace("http://", with: "https://") }
        return URL(string: s)
    }
}

public extension String {
    /// 去掉接口返回中的高亮 HTML 标签（如搜索结果里的 <font color='...'>）
    func strippingHTML() -> String {
        guard contains("<") else { return self }
        var out = ""
        var skipping = false
        for ch in self {
            if ch == "<" { skipping = true; continue }
            if ch == ">" { skipping = false; continue }
            if !skipping { out.append(ch) }
        }
        return out
    }

    /// "#RRGGBB" 十六进制颜色（不透明度 0~1）
    func hexColorAlpha(_ alpha: Double = 1) -> (red: Double, green: Double, blue: Double)? {
        var hex = trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let v = UInt64(hex, radix: 16) else { return nil }
        return (red: Double((v >> 16) & 0xFF) / 255,
                green: Double((v >> 8) & 0xFF) / 255,
                blue: Double(v & 0xFF) / 255)
    }
}

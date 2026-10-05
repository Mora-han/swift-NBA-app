import SwiftUI
import NBAKit

/// 新闻：虎扑 NBA 实时资讯流，正文在 App 内读，不跳浏览器。
///
/// 时效设计（两路接口分工，实测依据）：
/// - 列表用 `news/v2/MSite`：一次固定 100 条、覆盖近 4 小时、最新通常 1~2 分钟前。
///   而 `news/v2/newsList` 首页会滞后几十分钟，只适合往回翻历史。
/// - 页面可见期间每 30 秒静默拉一次实时流，新条目插到顶部；切回前台也会立刻刷一次。
/// - 「加载更多」用 newsList 的 newsId 游标，从当前最旧一条 nid 往回翻（实测严格递减且零重叠）。
struct NewsView: View {
    @State private var model = NewsModel()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("新闻")
                .inlineNavigationTitle()
                .refreshable { await model.reload() }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await model.reload() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("立即刷新")
                    }
                }
        }
        // 进入该栏目开始轮询，离开自动取消（.task 生命周期跟随视图）
        .task { await model.runPolling() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.refreshFeed(isAuto: true) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.items.isEmpty {
            LoadingBlock()
        } else if let error = model.errorMessage, model.items.isEmpty {
            FailureBlock(message: error) { Task { await model.refreshFeed(isAuto: false) } }
        } else if model.items.isEmpty {
            EmptyBlock(title: "暂无新闻", message: "虎扑 NBA 板块还没有新内容")
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                header

                ForEach(model.items) { item in
                    if let tid = item.tid?.raw, !tid.isEmpty {
                        NavigationLink {
                            NewsDetailView(tid: tid,
                                           previewTitle: item.title,
                                           previewTime: item.publishTime,
                                           previewReplies: item.replies)
                        } label: {
                            NewsRow(item: item)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // 少数纯外链条目（活动页等）只能跳浏览器
                        NewsRow(item: item)
                            .onTapGesture {
                                if let url = item.webURL { openURL(url) }
                            }
                    }
                }

                loadMoreBar
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
            .pageWidth(1000)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 状态头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("NBA 快讯")
                    .font(.system(size: 20, weight: .semibold))
                Spacer(minLength: 8)
                statusChip
            }

            Text("实时流 · 共 \(model.items.count) 条 · 更新于 \(Self.clock.string(from: model.lastUpdated ?? .now)) · 每 \(NewsModel.pollSeconds) 秒自动刷新")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        if model.newCount > 0 {
            Text("+\(model.newCount) 条新内容")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor, in: .capsule)
        } else if model.isRefreshing {
            HStack(spacing: 5) {
                ProgressView().controlSize(.small)
                Text("刷新中").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 4) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("已是最新").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var loadMoreBar: some View {
        if model.isLoadingMore {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        } else if model.hasMore {
            Button {
                Task { await model.loadMore() }
            } label: {
                Text("加载更早的新闻")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
        } else {
            Text("已到最早")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
    }

    /// 状态栏时间只用时分秒，配 monospacedDigit 不会跳动
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

// MARK: - 新闻行

private struct NewsRow: View {
    let item: NewsItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(urlString: item.img, width: 104, height: 72,
                        cornerRadius: 8, contentMode: .fill)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if item.isPinned {
                        Text("置顶")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(red: 1, green: 0.25, blue: 0.31),
                                        in: .rect(cornerRadius: 3))
                    }
                    Text(item.title ?? "")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    Text(relativeTime(item.publishDate))
                    if let replies = item.replies {
                        Label("\(replies)", systemImage: "bubble.right")
                    }
                    if let lights = item.lights, lights > 0 {
                        Label("\(lights)", systemImage: "hand.thumbsup")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .cardSurface()
        .contentShape(.rect)
    }

    /// 实时流用相对时间比绝对时间更有「新」的感觉
    private func relativeTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
        return "\(Int(seconds / 86400)) 天前"
    }
}

// MARK: - 模型

@MainActor
@Observable
final class NewsModel {
    /// 轮询间隔：实时流接口实测 0.1s 级响应，30 秒足够「即时」又不会给服务端压力
    static let pollSeconds = 30

    private(set) var items: [NewsItem] = []
    private(set) var isLoading = true
    private(set) var isRefreshing = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = true
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?
    private(set) var newCount = 0

    /// 已出现的 nid，实时流与历史翻页合并时去重
    private var seen: Set<String> = []
    /// 历史翻页游标：当前列表里最旧一条 nid
    private var cursor: String?
    private var badgeTask: Task<Void, Never>?
    private let client = HupuClient.shared

    /// 进入页面即轮询；视图消失时由 SwiftUI 取消整个 Task
    func runPolling() async {
        await refreshFeed(isAuto: false)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.pollSeconds))
            guard !Task.isCancelled else { return }
            await refreshFeed(isAuto: true)
        }
    }

    /// 手动刷新 / 下拉刷新：丢掉已翻的历史，回到最新一屏
    func reload() async {
        items = []
        seen = []
        cursor = nil
        hasMore = true
        newCount = 0
        await refreshFeed(isAuto: false)
    }

    /// 拉实时流并合并新条目。`isAuto` 为真时撞到新内容会亮一下角标。
    func refreshFeed(isAuto: Bool) async {
        if items.isEmpty { isLoading = true }
        isRefreshing = true
        defer {
            isLoading = false
            isRefreshing = false
        }

        // 轮询必须绕过缓存，否则 TTL 内会拿到同一份数据
        let root: NewsListRoot? = try? await client.fetch(
            .newsSite, ttl: HupuConfig.TTL.newsLive, forceRefresh: true)
        guard let root else {
            if items.isEmpty { errorMessage = "新闻加载失败" }
            return
        }
        errorMessage = nil

        var fresh: [NewsItem] = []
        for item in root.items where insert(item) { fresh.append(item) }
        if !fresh.isEmpty {
            items.append(contentsOf: fresh)
            sortByTimeDescending()
            if isAuto { flashBadge(fresh.count) }
        }
        lastUpdated = .now
    }

    /// 用当前最旧一条的 nid 当游标往更早翻（newsList 严格返回更旧的条目）
    func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let seed = cursor ?? oldestNid()
        guard let seed else {
            hasMore = false
            return
        }
        let root: NewsListRoot? = try? await client.fetch(
            .newsList(cursor: seed), ttl: HupuConfig.TTL.news)
        guard let root else { return }

        let batch = root.items
        let fresh = batch.filter { insert($0) }
        items.append(contentsOf: fresh)
        sortByTimeDescending()
        cursor = batch.last?.nid?.raw ?? seed
        if batch.isEmpty || fresh.isEmpty { hasMore = false }
    }

    // MARK: 内部

    private func insert(_ item: NewsItem) -> Bool {
        guard let nid = item.nid?.raw else { return true }   // 无 nid 的条目不去重
        return seen.insert(nid).inserted
    }

    private func oldestNid() -> String? {
        items.compactMap { $0.nid?.raw }.last
    }

    private func sortByTimeDescending() {
        items.sort { ($0.publishDate ?? .distantPast) > ($1.publishDate ?? .distantPast) }
    }

    private func flashBadge(_ count: Int) {
        newCount = count
        badgeTask?.cancel()
        badgeTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            newCount = 0
        }
    }
}

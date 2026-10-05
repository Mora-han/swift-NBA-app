import SwiftUI
import NBAKit

/// 比分主页：所有比赛按日期倒序（最新在最上）以卡片网格呈现，
/// 下滑到底部自动加载更早的历史比赛。
struct ScoresView: View {
    @State private var model = ScoresModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("比分")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        if model.hasLive {
                            HStack(spacing: 5) {
                                Circle().fill(Theme.live).frame(width: 7, height: 7)
                                Text("直播中").font(.caption.weight(.medium))
                            }
                            .foregroundStyle(Theme.live)
                            .transition(.opacity)
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await model.refresh(force: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(model.isRefreshing)
                    }
                }
                .refreshable { await model.refresh(force: true) }
        }
        .task { await model.start() }
    }

    @ViewBuilder
    private var content: some View {
        if model.isInitialLoading {
            LoadingBlock()
        } else if let error = model.errorMessage, model.sections.isEmpty {
            FailureBlock(message: error) {
                Task { await model.start(force: true) }
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    // 顶部：默认停在今日最新，向下拉（或点这里）才会展开未来赛程
                    if model.canShowNewer {
                        newerHeader
                    }

                    ForEach(model.sections) { section in
                        DaySection(section: section)
                    }

                    // 底部哨兵：进入视口即自动加载更早（历史）的比赛
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            guard model.canLoadOlder else { return }
                            Task { await model.loadOlder() }
                        }

                    footer
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 12)
                .pageWidth(1400)
            }
            .frame(maxWidth: .infinity)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newOffset in
                // 基准只增不减：记录用户曾经向下滚到的位置
                if !didCaptureRest || newOffset > restOffset {
                    restOffset = newOffset
                    didCaptureRest = true
                }
                // 只在手指真正按住拖动、且已拉过顶部时才加载未来赛程。
                // 列表首次布局、刷新回弹等非主动滚动都会走 .animating/.idle，
                // 否则首帧就会被当成「用户在上拉」，一进来就跳到未来赛程。
                guard scrollPhase == .tracking,
                      newOffset < restOffset - 6,
                      model.canLoadNewer else { return }
                restOffset = newOffset
                Task { await model.loadNewer() }
            }
            .onScrollPhaseChange { _, newPhase in scrollPhase = newPhase }
        }
    }

    /// 滚动静止时的顶部偏移，作为判断「上拉」的基准
    @State private var restOffset: CGFloat = 0
    @State private var didCaptureRest = false
    @State private var scrollPhase: ScrollPhase = .idle

    /// 顶部提示条：只有当用户主动上拉时才会出现未来赛程
    @ViewBuilder
    private var newerHeader: some View {
        if model.isLoadingNewer {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在加载未来赛程…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if model.canLoadNewer {
            Button {
                Task { await model.loadNewer() }
            } label: {
                footerLabel("下拉查看未来赛程", systemImage: "arrow.up")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    /// 上下两端的状态提示：正在加载 / 可以继续加载 / 已到边界
    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 10) {
            if model.isLoadingOlder || model.isLoadingNewer {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.isLoadingOlder ? "正在加载更早的比赛…" : "正在加载更晚的赛程…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else if model.canLoadOlder {
                Button {
                    Task { await model.loadOlder() }
                } label: {
                    footerLabel("加载更早的比赛", systemImage: "arrow.down")
                }
                .buttonStyle(.plain)
            } else if !model.sections.isEmpty {
                Text("已加载到 \(model.oldestDayText)")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func footerLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(.quaternary, in: .capsule)
    }
}

// MARK: - 单日分组

private struct DaySection: View {
    let section: ScheduleSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if section.matches.isEmpty {
                Text("当日无比赛")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 22)
                    .cardSurface()
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(section.matches) { match in
                        NavigationLink {
                            MatchDetailView(matchId: match.matchId ?? "", initial: match)
                        } label: {
                            MatchCard(match: match)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 12)]
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(section.dayBlock)
                .font(.system(size: 19, weight: .bold))
            if section.isToday {
                Text("今天")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: .capsule)
            }
            if section.liveCount > 0 {
                HStack(spacing: 4) {
                    Circle().fill(Theme.live).frame(width: 6, height: 6)
                    Text("\(section.liveCount) 场直播")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Theme.live)
            }
            Spacer(minLength: 0)
            Text("\(section.matches.count) 场")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 比赛卡片

/// 竖排卡片：队徽 + 队名 + 大比分，比矮条式更具视觉重量
struct MatchCard: View {
    let match: Match

    private var awayWon: Bool {
        guard match.isFinished, let w = match.winTeamName else { return false }
        return w == match.awayTeamName
    }

    private var homeWon: Bool {
        guard match.isFinished, let w = match.winTeamName else { return false }
        return w == match.homeTeamName
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                statusBadge
                Spacer(minLength: 0)
                if let stage = match.competitionStageDesc, !stage.isEmpty {
                    Text(stage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            VStack(spacing: 8) {
                teamRow(name: match.awayTeamName, logo: match.awayTeamLogo,
                        score: match.awayScore, rank: match.awayRank, won: awayWon)
                Divider()
                teamRow(name: match.homeTeamName, logo: match.homeTeamLogo,
                        score: match.homeScore, rank: match.homeRank, won: homeWon)
            }
        }
        .padding(14)
        .cardSurface()
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch match.status {
        case .inPlay:
            HStack(spacing: 5) {
                Circle().fill(Theme.live).frame(width: 6, height: 6)
                Text(quarterText)
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.live)
        case .notStarted:
            Text(match.startTime?.formatted(date: .omitted, time: .shortened) ?? "--:--")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        case .finished:
            Text("完场")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        default:
            Text(match.matchStatusChinese ?? "")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var quarterText: String {
        guard let q = match.currentQuarter, q > 0 else { return "直播" }
        return "第\(q)节"
    }

    private func teamRow(name: String?, logo: String?, score: Int?,
                         rank: String?, won: Bool) -> some View {
        HStack(spacing: 10) {
            RemoteImage(urlString: logo, width: 34, height: 34)

            if let rank, Int(rank) != nil {
                Text(rank)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            } else {
                Color.clear.frame(width: 18, height: 1)
            }

            Text(name ?? "-")
                .font(.system(size: 16, weight: won ? .bold : .regular))
                .foregroundStyle(won ? .primary : .secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let score {
                Text("\(score)")
                    .font(.scoreNumber(26))
                    .monospacedDigit()
                    .foregroundStyle(won ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentTransition(.numericText())
            } else {
                Text("–")
                    .font(.scoreNumber(22))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - 模型

@MainActor
@Observable
final class ScoresModel {
    /// 已加载的比赛，按日期倒序（最新在最上）
    private(set) var sections: [ScheduleSection] = []
    private(set) var isInitialLoading = true
    private(set) var isRefreshing = false
    private(set) var isLoadingOlder = false
    private(set) var isLoadingNewer = false
    private(set) var errorMessage: String?

    /// 已加载到的最早 / 最晚一天（yyyyMMdd），继续翻页的锚点
    private(set) var oldestDay: String
    private(set) var newestDay: String
    /// 服务端可提供的最早 / 最晚日期；到达边界后不再继续加载
    private var serverEarliestDay: String?
    private var serverLatestDay: String?
    private var didReachServerStart = false
    private var didReachServerEnd = false
    /// 是否已经允许展示今天之后的赛程。首次进入时接口窗口会直接带到未来，
    /// 但用户要求默认停在「今日最新」，所以向上拉之前先把未来日期藏起来。
    private var includeFuture = false

    private let client = HupuClient.shared
    private var pollTask: Task<Void, Never>?

    init(today: String = Date.compactDayKey) {
        oldestDay = today
        newestDay = today
    }

    var hasLive: Bool {
        sections.flatMap(\.matches).contains { $0.isLive }
    }

    /// 向下拉：还有更早的比赛
    var canLoadOlder: Bool {
        guard !isLoadingOlder, !isLoadingNewer, !sections.isEmpty, !didReachServerEnd else { return false }
        if let earliest = serverEarliestDay, let oldest = Date.parseCompactDayKey(oldestDay),
           let earliestDate = Date.parseCompactDayKey(earliest) {
            if oldest <= earliestDate { return false }
        }
        return true
    }

    /// 向上拉：还有更晚（未来赛程）的比赛
    var canLoadNewer: Bool {
        guard !isLoadingNewer, !isLoadingOlder, !sections.isEmpty, !didReachServerStart else { return false }
        if let latest = serverLatestDay, let newest = Date.parseCompactDayKey(newestDay),
           let latestDate = Date.parseCompactDayKey(latest) {
            if newest >= latestDate { return false }
        }
        return true
    }

    /// 未来赛程默认收起，只有用户主动上拉/点击才展开
    var canShowNewer: Bool { !includeFuture && canLoadNewer }

    var oldestDayText: String {
        guard let date = Date.parseCompactDayKey(oldestDay) else { return "最早记录" }
        return "\(date.formatted(.dateTime.year().month().day()))"
    }

    func start(force: Bool = false) async {
        if !force, !sections.isEmpty { return }
        await load(anchor: Date.compactDayKey)
        startPolling()
    }

    func refresh(force: Bool) async {
        await load(anchor: sections.isEmpty ? Date.compactDayKey : todayAnchor, force: force)
    }

    private var todayAnchor: String { Date.compactDayKey }

    /// 向下拉到底：锚点前移 7 天，取更早的一个窗口并合并
    func loadOlder() async {
        guard canLoadOlder else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        await extend(.older)
    }

    /// 向上拉到底：锚点后移 7 天，取更晚的一个窗口并合并
    func loadNewer() async {
        guard canLoadNewer else { return }
        isLoadingNewer = true
        defer { isLoadingNewer = false }
        await extend(.newer)
    }

    private enum Direction { case older, newer }

    /// 按新锚点取一个窗口，只保留朝该方向更远的日期并合并。
    /// 接口的 day 是「以该日为中心」的窗口，一次大约覆盖前后若干天，
    /// 所以每翻一页推进 7 天，窗口之间既能接上又不会过度重叠。
    private func extend(_ direction: Direction) async {
        if direction == .newer { includeFuture = true }
        let anchor = direction == .older ? oldestDay : newestDay
        let offset = direction == .older ? -7 : 7
        guard let next = Date.compactDayKey(offsetDays: offset, from: anchor) else {
            markEnd(direction); return
        }

        let root: ScheduleRoot? = try? await client.fetch(
            .scheduleList(day: next), ttl: HupuConfig.TTL.schedule)
        guard let root else { return }

        let stats = root.scheduleListStats
        if let earliest = stats?.earliestDate { serverEarliestDay = earliest }
        if let latest = stats?.latestDate { serverLatestDay = latest }

        let incoming = (root.gameList ?? [])
            .map { ScheduleSection(day: $0) }
            .filter { direction == .older ? $0.day < anchor : $0.day > anchor }

        merge(incoming)
        // 窗口里没有更远的日期时也要推进锚点，否则会反复请求同一窗口
        if incoming.isEmpty { advance(direction, to: next) }
        checkBoundaries()
    }

    private func advance(_ direction: Direction, to day: String) {
        if direction == .older { oldestDay = day } else { newestDay = day }
    }

    private func markEnd(_ direction: Direction) {
        if direction == .older { didReachServerEnd = true } else { didReachServerStart = true }
    }

    private func checkBoundaries() {
        if let earliest = serverEarliestDay, let e = Date.parseCompactDayKey(earliest),
           let o = Date.parseCompactDayKey(oldestDay), o <= e {
            didReachServerEnd = true
        }
        if let latest = serverLatestDay, let l = Date.parseCompactDayKey(latest),
           let n = Date.parseCompactDayKey(newestDay), n >= l {
            didReachServerStart = true
        }
    }

    private func merge(_ incoming: [ScheduleSection]) {
        guard !incoming.isEmpty else { return }
        var map: [String: ScheduleSection] = [:]
        for section in sections { map[section.day] = section }
        for section in incoming {
            if let existing = map[section.day] {
                map[section.day] = existing.merging(section)
            } else {
                map[section.day] = section
            }
        }

        // 翻页锚点按「已见数据的真实范围」推进，不能用展示列表的首尾：
        // 今天没有比赛时列表首尾并不是真正的最新/最早日期，会导致翻页卡死。
        let allDays = map.keys.sorted()
        if let first = allDays.first { oldestDay = first }
        if let last = allDays.last { newestDay = last }

        let today = Date.compactDayKey
        sections = (includeFuture ? Array(map.values) : map.values.filter { $0.day <= today })
            .sorted { $0.day > $1.day }
    }

    private func load(anchor: String, force: Bool = false) async {
        if !sections.isEmpty { isRefreshing = true }
        defer { isRefreshing = false; isInitialLoading = false }

        // 接口的 day 参数是「以该日为中心」的窗口锚点，能覆盖到真实赛程；
        // 不传 day 时虎扑会返回一个被季后赛残留占据的旧窗口，导致真实比赛看不到。
        let root: ScheduleRoot
        do {
            root = try await client.fetch(.scheduleList(day: anchor),
                                          ttl: HupuConfig.TTL.schedule,
                                          forceRefresh: force)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }

        if let earliest = root.scheduleListStats?.earliestDate { serverEarliestDay = earliest }
        if let latest = root.scheduleListStats?.latestDate { serverLatestDay = latest }

        merge((root.gameList ?? []).map { ScheduleSection(day: $0) })
        errorMessage = nil
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(HupuConfig.scoresRefreshInterval))
                guard !Task.isCancelled else { return }
                await refresh(force: true)
            }
        }
    }
}

// MARK: - 日期分组模型

/// 一天的比赛（比分页的一节）
struct ScheduleSection: Identifiable, Hashable {
    let day: String
    let dayBlock: String
    let matches: [Match]

    var id: String { day }

    var isToday: Bool { day == Date.compactDayKey }

    var liveCount: Int { matches.filter(\.isLive).count }

    init(day: ScheduleDay) {
        self.day = day.day ?? ""
        self.dayBlock = day.dayBlock ?? Date.dayBlockText(for: day.day)
        self.matches = day.matches
    }

    /// 合并同一天的多批数据（同一场比赛可能在相邻窗口里重复出现）
    func merging(_ other: ScheduleSection) -> ScheduleSection {
        var map: [String: Match] = [:]
        var order: [String] = []
        for match in matches {
            let key = match.matchId ?? UUID().uuidString
            map[key] = match
            order.append(key)
        }
        for match in other.matches {
            let key = match.matchId ?? UUID().uuidString
            if map[key] == nil { order.append(key) }
            map[key] = match
        }
        return ScheduleSection(day: day, dayBlock: dayBlock,
                               matches: order.compactMap { map[$0] })
    }

    private init(day: String, dayBlock: String, matches: [Match]) {
        self.day = day
        self.dayBlock = dayBlock
        self.matches = matches
    }
}

// MARK: - 日期工具

extension Date {
    /// 今天（北京时间）的 yyyyMMdd
    static var compactDayKey: String {
        compactDayKey(for: .now)
    }

    static func compactDayKey(for date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    static func compactDayKey(offsetDays: Int, from key: String) -> String? {
        guard let base = parseCompactDayKey(key) else { return nil }
        return compactDayKey(for: base.addingTimeInterval(Double(offsetDays) * 86400))
    }

    static func parseCompactDayKey(_ key: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f.date(from: key)
    }

    /// 接口缺 dayBlock 时的兜底文案："10月9日 周五"
    static func dayBlockText(for key: String?) -> String {
        guard let key, let date = parseCompactDayKey(key) else { return "" }
        let weekday: String
        switch date.formatted(.dateTime.weekday(.abbreviated)) {
        case "Sun": weekday = "周日"
        case "Mon": weekday = "周一"
        case "Tue": weekday = "周二"
        case "Wed": weekday = "周三"
        case "Thu": weekday = "周四"
        case "Fri": weekday = "周五"
        case "Sat": weekday = "周六"
        default: weekday = ""
        }
        return "\(date.formatted(.dateTime.month().day()))日 \(weekday)"
    }
}

import SwiftUI
import NBAKit

/// 比分主页：横向日期条 + 按日分组的比赛列表，30s 自动刷新。
struct ScoresView: View {
    @State private var model = ScoresModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("比分")
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        HStack(spacing: 2) {
                            Button {
                                Task { await model.step(by: -1) }
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            Button {
                                Task { await model.step(by: 1) }
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            Button {
                                Task { await model.select(day: Date.compactDayKey) }
                            } label: {
                                Text("今天").font(.subheadline)
                            }
                        }
                        .disabled(model.isRefreshing)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if model.hasLive {
                            HStack(spacing: 4) {
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
        } else if let error = model.errorMessage, model.days.isEmpty {
            FailureBlock(message: error) {
                Task { await model.start(force: true) }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 14, pinnedViews: [.sectionHeaders]) {
                    Section {
                        if let day = model.selectedDayObject, day.day == model.anchorDate {
                            DaySection(day: day, matches: day.matches)
                        } else {
                            EmptyBlock(title: "该日暂无赛程", message: "换个日期看看")
                        }
                    } header: {
                        DayStrip(model: model)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
                .readableWidth()
            }
        }
    }
}

// MARK: - 顶部日期条（pinned）

private struct DayStrip: View {
    @Bindable var model: ScoresModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.days) { day in
                            Button {
                                Task { await model.select(day: day.day ?? "") }
                            } label: {
                                VStack(spacing: 1) {
                                    Text(day.shortWeekday)
                                        .font(.caption2)
                                        .opacity(0.8)
                                        .lineLimit(1)
                                    Text(day.dayOfMonth)
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                        .lineLimit(1)
                                    Circle()
                                        .fill(model.liveMatchCount(on: day) > 0 ? Theme.live : .clear)
                                        .frame(width: 4, height: 4)
                                }
                                .frame(width: 44, height: 54)
                                .background(
                                    model.anchorDate == day.day
                                        ? Color.accentColor
                                        : Color(.tertiarySystemFill),
                                    in: .rect(cornerRadius: 12)
                                )
                                .foregroundStyle(model.anchorDate == day.day ? .white : .primary)
                                .id(day.day)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    proxy.scrollTo(model.anchorDate, anchor: .center)
                }
                .onChange(of: model.anchorDate) { _, selected in
                    withAnimation(.easeInOut) { proxy.scrollTo(selected, anchor: .center) }
                }
            }
            Divider()
        }
        .background(stripBackground)
    }

    /// 日期条背景：iOS 用系统 bar 材质（参与 Liquid Glass 折射），
    /// macOS 用窗口材质（顶栏式材质在桌面端观感不对）
    private var stripBackground: some View {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}

// MARK: - 单日分组

private struct DaySection: View {
    let day: ScheduleDay
    let matches: [Match]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day.dayBlock ?? "")
                .font(.headline)
                .padding(.top, 4)

            if matches.isEmpty {
                Text("当日无比赛")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
                    .cardSurface()
            } else {
                ForEach(matches) { match in
                    NavigationLink {
                        MatchDetailView(matchId: match.matchId ?? "", initial: match)
                    } label: {
                        MatchRow(match: match)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 比赛行

struct MatchRow: View {
    let match: Match

    var body: some View {
        HStack(spacing: 10) {
            statusBadge

            teamBlock(name: match.awayTeamName, logo: match.awayTeamLogo, score: match.awayScore, rank: match.awayRank)
            VStack(spacing: 1) {
                Text("VS")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            teamBlock(name: match.homeTeamName, logo: match.homeTeamLogo, score: match.homeScore, rank: match.homeRank)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .cardSurface()
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch match.status {
        case .inPlay:
            HStack(spacing: 3) {
                Circle().fill(Theme.live).frame(width: 5, height: 5)
                Text(quarterText)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.live)
            .frame(width: 46, alignment: .leading)
        case .notStarted:
            Text(match.startTime?.formatted(date: .omitted, time: .shortened) ?? "--:--")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
        case .finished:
            Text("完场")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 46, alignment: .leading)
        default:
            Text(match.matchStatusChinese ?? "")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
        }
    }

    private var quarterText: String {
        guard let q = match.currentQuarter, q > 0 else { return "直播" }
        return "第\(q)节"
    }

    private func teamBlock(name: String?, logo: String?, score: Int?, rank: String?) -> some View {
        HStack(spacing: 6) {
            Text(name ?? "-")
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)

            if let score {
                Text("\(score)")
                    .font(.scoreNumber(17))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 34, alignment: .trailing)
            } else {
                Color.clear.frame(width: 34, height: 1)
            }

            if let rank, !rank.isEmpty, Int(rank) != nil {
                Text(rank)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: .rect(cornerRadius: 3))
            }

            RemoteImage(urlString: logo, width: 24, height: 24)
        }
    }
}

// MARK: - 模型

@MainActor
@Observable
final class ScoresModel {
    /// 以选中日期为中心，前后各一周（接口单次窗口约 ±5~13 天）
    private(set) var days: [ScheduleDay] = []
    private(set) var isInitialLoading = true
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

    /// 当前浏览的日期（yyyyMMdd），日期条与列表都基于它
    private(set) var anchorDate: String

    private let client = HupuClient.shared
    private var pollTask: Task<Void, Never>?

    init(today: String = Date.compactDayKey) {
        anchorDate = today
    }

    var selectedDay: String { anchorDate }

    var hasLive: Bool {
        days.flatMap(\.matches).contains { $0.isLive }
    }

    var selectedDayObject: ScheduleDay? {
        days.first { $0.day == anchorDate } ?? days.first
    }

    func liveMatchCount(on day: ScheduleDay) -> Int {
        day.matches.filter(\.isLive).count
    }

    func start(force: Bool = false) async {
        if !force, !days.isEmpty { return }
        await load(anchor: anchorDate)
        startPolling()
    }

    /// 切换日期：锚点变更后重新取该日期前后一周的窗口
    func select(day: String) async {
        guard day != anchorDate else { return }
        anchorDate = day
        days = []
        await load(anchor: day)
    }

    /// 左右翻页（一天一天翻，符合日期条交互）
    func step(by offset: Int) async {
        guard let target = Date.compactDayKey(offsetDays: offset, from: anchorDate) else { return }
        await select(day: target)
    }

    func refresh(force: Bool) async {
        await load(anchor: anchorDate, force: force)
    }

    private func load(anchor: String, force: Bool = false) async {
        if !days.isEmpty { isRefreshing = true }
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

        let list = root.gameList ?? []
        days = list.sorted { ($0.day ?? "") < ($1.day ?? "") }
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
}

// MARK: - ScheduleDay 便利字段

extension ScheduleDay {
    /// "20261004" → Date
    var date: Date? {
        guard let day else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: day)
    }

    /// 仅日号，配合 weekday 做紧凑日期条
    var dayOfMonth: String {
        guard let date else { return "" }
        return "\(date.formatted(.dateTime.day()))日"
    }

    var shortDay: String {
        guard let date else { return day ?? "" }
        return "\(date.formatted(.dateTime.month(.defaultDigits)))月\(date.formatted(.dateTime.day()))日"
    }

    var shortWeekday: String {
        guard let date else { return "" }
        switch date.formatted(.dateTime.weekday(.abbreviated)) {
        case "Sun": return "周日"
        case "Mon": return "周一"
        case "Tue": return "周二"
        case "Wed": return "周三"
        case "Thu": return "周四"
        case "Fri": return "周五"
        case "Sat": return "周六"
        default: return ""
        }
    }
}
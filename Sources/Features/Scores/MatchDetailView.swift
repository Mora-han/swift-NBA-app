import SwiftUI
import NBAKit

/// 比赛详情：比分头图 + 实时文字直播 + 两队技术统计 + 球员 boxscore
struct MatchDetailView: View {
    let matchId: String
    let initial: Match

    @State private var model: MatchDetailModel

    init(matchId: String, initial: Match) {
        self.matchId = matchId
        self.initial = initial
        _model = State(initialValue: MatchDetailModel(matchId: matchId, initial: initial))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScoreBoardCard(match: model.displayMatch)

                // 未开赛 / 已取消的比赛没有任何统计数据，直接给出说明而不是空卡片
                if model.hasStatistics {
                    if let comparison = model.comparison {
                        TeamComparisonCard(stats: comparison)
                    }
                    if let box = model.boxscore {
                        BoxscoreSection(boxscore: box,
                                        awayTeamName: model.displayMatch.awayTeamName,
                                        homeTeamName: model.displayMatch.homeTeamName,
                                        awayTeamId: model.displayMatch.awayTeamId,
                                        homeTeamId: model.displayMatch.homeTeamId)
                    }
                } else {
                    UnavailableMatchNote(status: model.displayMatch.status,
                                         time: model.displayMatch.startTime)
                }

                LiveFeedSection(feed: model.liveFeed)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 12)
            .readableWidth(820)
        }
        .navigationTitle("比赛详情")
        .inlineNavigationTitle()
        .pageBackground()
        .task { await model.start() }
        .onDisappear { model.stop() }
        .refreshable { await model.reload() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model.isLive {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.live).frame(width: 7, height: 7)
                        Text("LIVE")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(Theme.live)
                }
            }
        }
    }
}

// MARK: - 比分头卡

private struct ScoreBoardCard: View {
    let match: Match

    var body: some View {
        VStack(spacing: 14) {
            // 顶部品牌色渐变，Liquid Glass 会自动折射下层内容
            HStack {
                stageTag
                Spacer()
                if let tv = match.matchTvList?.first, let url = HupuMedia.imageURL(tv.tvUrl) {
                    Link(destination: url) {
                        Label(tv.tvName ?? "直播", systemImage: "play.tv.fill")
                            .font(.caption)
                    }
                }
            }

            HStack(alignment: .center, spacing: 14) {
                teamColumn(name: match.awayTeamName, logo: match.awayTeamLogo,
                           score: match.awayScore, rank: match.awayRank,
                           color: match.awayTeamDayColor)

                VStack(spacing: 4) {
                    Text(statusText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(match.isLive ? Theme.live : .secondary)
                    if let time = match.startTime, !match.isFinished {
                        Text(time.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    if let arena = match.arenaCity, !arena.isEmpty {
                        Text(arena)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(minWidth: 78)

                teamColumn(name: match.homeTeamName, logo: match.homeTeamLogo,
                           score: match.homeScore, rank: match.homeRank,
                           color: match.homeTeamDayColor)
            }

            if let memo = match.memo, !memo.isEmpty {
                Text(memo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .systemCard()
        .background {
            // 品牌色氛围层（玻璃材质下方）
            LinearGradient(
                colors: [Color(hex: match.awayTeamDayColor).opacity(0.25),
                         Color(hex: match.homeTeamDayColor).opacity(0.25)],
                startPoint: .leading, endPoint: .trailing
            )
            .allowsHitTesting(false)
        }
    }

    private var statusText: String {
        switch match.status {
        case .inPlay: return "第\(match.currentQuarter ?? 0)节进行中"
        case .finished: return "已结束"
        case .notStarted: return "未开始"
        case .cancelled: return "已取消"
        case .postponed: return "已延期"
        case .other(let s): return s
        }
    }

    @ViewBuilder
    private var stageTag: some View {
        if let desc = match.competitionStageDesc, !desc.isEmpty {
            Text(desc)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: .capsule)
        }
    }

    private func teamColumn(name: String?, logo: String?, score: Int?,
                            rank: String?, color: String?) -> some View {
        VStack(spacing: 6) {
            RemoteImage(urlString: logo, width: 56, height: 56)
            Text(name ?? "-")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 6) {
                if let rank, Int(rank) != nil {
                    Text(rank)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color(hex: color, fallback: .gray), in: .capsule)
                }
                Text(score.map(String.init) ?? "–")
                    .font(.scoreNumber(34))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 两队技术统计对比

private struct TeamComparisonCard: View {
    let stats: TeamMatchStats

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "两队对比", subtitle: "上为客队，下为主队")

            VStack(spacing: 2) {
                ForEach(stats.compares) { item in
                    CompareBar(item: item)
                }
            }
        }
        .systemCard()
    }
}

private struct CompareBar: View {
    let item: StatCompare

    /// 拆出主数值与括号内的命中-出手
    private func parts(_ raw: String?) -> (main: String, sub: String?) {
        let text = raw ?? "-"
        let seg = text.split(separator: " ", maxSplits: 1).map(String.init)
        return (seg.first ?? "-", seg.count > 1 ? seg[1] : nil)
    }

    var body: some View {
        let homeVal = item.homeVal ?? 0
        let awayVal = item.awayVal ?? 0
        let total = homeVal + awayVal
        let awayRatio = total > 0 ? awayVal / total : 0.5
        let away = parts(item.away?.raw)
        let home = parts(item.home?.raw)

        VStack(spacing: 3) {
            // 客队：名字在左、数字在右
            HStack(spacing: 8) {
                Text(item.name ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                if let sub = away.sub {
                    Text(sub)
                        .font(.statNumber(10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Text(away.main)
                    .font(.statNumber(15, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(minWidth: 46, alignment: .trailing)
            }

            // 条形：上段客队占比、下段主队占比
            GeometryReader { geo in
                let w = geo.size.width
                let gap: CGFloat = 2
                let segH = max(3, (geo.size.height - gap) / 2)
                VStack(spacing: gap) {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: max(4, w * awayRatio), height: segH)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Capsule()
                        .fill(Color.accentColor.opacity(0.32))
                        .frame(width: max(4, w * (1 - awayRatio)), height: segH)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(height: segH * 2 + gap)
            }
            .frame(height: 10)

            // 主队：数字在左
            HStack(spacing: 8) {
                Text(home.main)
                    .font(.statNumber(15, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(minWidth: 46, alignment: .leading)
                if let sub = home.sub {
                    Text(sub)
                        .font(.statNumber(10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
            }
        }
    }
}

// MARK: - 球员技术统计（boxscore）

/// 按主客队分栏展示，照片放大到能看清
private struct BoxscoreSection: View {
    let boxscore: Boxscore
    let awayTeamName: String?
    let homeTeamName: String?
    let awayTeamId: String?
    let homeTeamId: String?

    @State private var side: Side = .away

    enum Side: Hashable { case away, home }

    private var currentTeamName: String {
        side == .away ? (awayTeamName ?? "客队") : (homeTeamName ?? "主队")
    }

    private var players: [BoxscoreEntry] {
        boxscore.roster.filter { entry in
            let tid = entry.stats?.teamId
            switch side {
            case .away: return tid == nil || tid == awayTeamId
            case .home: return tid == nil || tid == homeTeamId
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "球员技术统计")

            // 主客队切换
            Picker("", selection: $side) {
                Text(awayTeamName ?? "客队").tag(Side.away)
                Text(homeTeamName ?? "主队").tag(Side.home)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if players.isEmpty {
                Text("\(currentTeamName) 暂无球员数据")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(players.enumerated()), id: \.element.id) { index, entry in
                        if let stats = entry.stats {
                            playerRow(stats: stats, tags: entry.tagInfoList ?? [])
                        }
                        if index < players.count - 1 {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
            }

            if !boxscore.officials.isEmpty {
                Text("裁判：" + boxscore.officials.compactMap { $0.stats?.name }.joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .systemCard()
    }

    private func playerRow(stats: PlayerMatchStats, tags: [PlayerTag]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // 照片放大：30 -> 52，能看清球员
                RemoteImage(urlString: stats.photo ?? stats.logoUrl,
                            width: 52, height: 52, cornerRadius: 8, contentMode: .fill)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if stats.isStarter {
                            Text("首发")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentColor, in: .rect(cornerRadius: 3))
                        }
                        Text(stats.name ?? "")
                            .font(.headline)
                            .lineLimit(1)
                        if stats.isOnCourt {
                            Image(systemName: "figure.basketball")
                                .font(.caption2)
                                .foregroundStyle(Theme.live)
                        }
                    }
                    HStack(spacing: 5) {
                        if let pos = stats.position, !pos.isEmpty {
                            Text(pos)
                        }
                        Text("背号 \(stats.number ?? "-")")
                        if let pm = stats.plusMinus?.raw, !pm.isEmpty, pm != "-" {
                            Text("正负 \(pm)")
                                .foregroundStyle(pm.hasPrefix("-")
                                                 ? Theme.loss : Theme.win)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    if !tags.isEmpty {
                        Text(tags.compactMap(\.text).joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
            }

            if stats.didNotPlay {
                Text("未出战")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 0) {
                    statCell("上场", stats.mins?.raw ?? "-")
                    statCell("得分", stats.pts.map(String.init) ?? "-",
                             highlight: (stats.pts ?? 0) >= 20)
                    statCell("篮板", stats.reb.map(String.init) ?? "-")
                    statCell("助攻", stats.asts.map(String.init) ?? "-")
                    statCell("抢断", stats.stl.map(String.init) ?? "-")
                    statCell("盖帽", stats.blk.map(String.init) ?? "-")
                    statCell("投篮", stats.fgp?.raw ?? "-")
                }
            }
        }
        .padding(.vertical, 10)
    }

    private func statCell(_ title: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.statNumber(14, weight: highlight ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(highlight ? Color.accentColor : .primary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 无数据说明

private struct UnavailableMatchNote: View {
    let status: MatchStatus
    let time: Date?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .systemCard()
    }

    private var icon: String {
        switch status {
        case .cancelled: return "xmark.circle"
        case .postponed: return "clock.badge.xmark"
        default: return "clock"
        }
    }

    private var title: String {
        switch status {
        case .cancelled: return "比赛已取消"
        case .postponed: return "比赛已延期"
        default: return "比赛尚未开始"
        }
    }

    private var detail: String {
        if let time, status == .notStarted {
            return "开赛时间 " + time.formatted(date: .abbreviated, time: .shortened)
        }
        return "暂无技术统计与文字直播"
    }
}

// MARK: - 文字直播

private struct LiveFeedSection: View {
    let feed: LiveFeed?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "比赛进程", subtitle: feed == nil ? nil : "每 12 秒自动更新")

            let ordered = (feed?.plays ?? []).sorted { ($0.sequence_id ?? 0) > ($1.sequence_id ?? 0) }
            let plays = Array(ordered.prefix(40))

            if plays.isEmpty {
                Text("暂无文字直播")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(plays)) { play in
                        HStack(alignment: .top, spacing: 8) {
                            Text("第\(play.section ?? 0)节")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(play.event ?? "")
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(play.vs ?? "")
                                    .font(.statNumber(13, weight: .semibold))
                                    .monospacedDigit()
                                if let t = play.left_time, t != "00" {
                                    Text(t)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Divider() }
                    }
                }
            }
        }
        .systemCard()
    }
}

// MARK: - 模型

@MainActor
@Observable
final class MatchDetailModel {
    private(set) var displayMatch: Match
    private(set) var liveFeed: LiveFeed?
    private(set) var comparison: TeamMatchStats?
    private(set) var boxscore: Boxscore?
    private(set) var isLive: Bool

    /// 该场是否应该展示统计数据（未开赛/取消的比赛接口只会返回空壳）
    var hasStatistics: Bool {
        switch displayMatch.status {
        case .inPlay, .finished: return true
        default: return false
        }
    }

    private let matchId: String
    private let client = HupuClient.shared
    private var pollTask: Task<Void, Never>?

    init(matchId: String, initial: Match) {
        self.matchId = matchId
        self.displayMatch = initial
        self.isLive = initial.isLive
    }

    func start() async {
        await reload()
        guard isLive else { return }
        startPolling()
    }

    func reload() async {
        async let info: Match? = try? await client.fetch(.matchInfo(matchId: matchId))
        async let compare: TeamMatchStats? = try? await client.fetch(.teamMatchStats(matchId: matchId))
        async let home: Boxscore? = try? await client.fetch(
            .boxscore(matchId: matchId, teamId: displayMatch.homeTeamId ?? ""))
        async let away: Boxscore? = try? await client.fetch(
            .boxscore(matchId: matchId, teamId: displayMatch.awayTeamId ?? ""))

        let (i, c, h, a) = await (info, compare, home, away)
        if let i { displayMatch = i; isLive = i.isLive }
        comparison = c
        boxscore = merge(home: h, away: a)
    }

    /// 主客队各调一次 boxscore，合并成一个列表
    private func merge(home: Boxscore?, away: Boxscore?) -> Boxscore? {
        guard home != nil || away != nil else { return nil }
        let merged = (away?.roster ?? []) + (home?.roster ?? [])
        let officials = home?.officials ?? away?.officials ?? []
        return Boxscore(merged: merged, officials: officials)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                let feed: LiveFeed? = try? await client.fetch(.live(matchId: matchId))
                if !Task.isCancelled { liveFeed = feed }
                try? await Task.sleep(for: .seconds(HupuConfig.livePollInterval))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

}
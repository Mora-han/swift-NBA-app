import SwiftUI
import NBAKit

/// 比赛详情：比分头图 + 实时文字直播 + 两队技术统计 + 球员 boxscore
struct MatchDetailView: View {
    let matchId: String

    @State private var model: MatchDetailModel

    init(matchId: String, initial: Match) {
        self.matchId = matchId
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
            .pageWidth(1200)
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
                            .font(.system(size: 13))
                    }
                }
            }

            HStack(alignment: .center, spacing: 14) {
                teamColumn(name: match.awayTeamName, logo: match.awayTeamLogo,
                           score: match.awayScore, rank: match.awayRank,
                           color: match.awayTeamDayColor)

                VStack(spacing: 4) {
                    Text(statusText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(match.isLive ? Theme.live : .secondary)
                        .multilineTextAlignment(.center)
                    if let time = match.startTime, !match.isFinished {
                        Text(time.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    if let arena = match.arenaCity, !arena.isEmpty {
                        Text(arena)
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(minWidth: 96)

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
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.quaternary, in: .capsule)
        }
    }

    private func teamColumn(name: String?, logo: String?, score: Int?,
                            rank: String?, color: String?) -> some View {
        VStack(spacing: 8) {
            RemoteImage(urlString: logo, width: 76, height: 76)
            Text(name ?? "-")
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1)
            HStack(spacing: 8) {
                if let rank, Int(rank) != nil {
                    Text(rank)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: color, fallback: .gray), in: .capsule)
                }
                Text(score.map(String.init) ?? "–")
                    .font(.scoreNumber(44))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 两队技术统计对比

/// 两队数据完全对齐：客队在左、主队在右，同一条横条左右分段表达占比。
/// 指标名独占一行，不再和横条挤在一起。
private struct TeamComparisonCard: View {
    let stats: TeamMatchStats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "两队对比", subtitle: "左客队 · 右主队")

            VStack(spacing: 16) {
                ForEach(stats.compares) { item in
                    CompareRow(item: item)
                }
            }
        }
        .systemCard()
    }
}

private struct CompareRow: View {
    let item: StatCompare

    /// 拆出主数值与括号内的命中-出手，例如 "50.6%(43-85)" → ("50.6%", "43-85")
    private func parts(_ raw: String?) -> (main: String, sub: String?) {
        let text = raw ?? "-"
        guard let range = text.firstIndex(of: "("), text.hasSuffix(")") else {
            return (text, nil)
        }
        let main = String(text[text.startIndex..<range])
        let sub = String(text[range...])
        return (main, sub)
    }

    private var away: (main: String, sub: String?) { parts(item.away?.raw) }
    private var home: (main: String, sub: String?) { parts(item.home?.raw) }

    private var awayWins: Bool {
        guard let a = item.awayVal, let h = item.homeVal else { return false }
        return a > h
    }

    private var homeWins: Bool {
        guard let a = item.awayVal, let h = item.homeVal else { return false }
        return h > a
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 指标名独占一行
            Text(item.name ?? "")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 客队值（左）— 横条 — 主队值（右），三者基线对齐
            HStack(alignment: .center, spacing: 12) {
                valueCell(away.main, sub: away.sub, highlight: awayWins)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                CompareBar(awayRatio: awayRatio, awayWins: awayWins, homeWins: homeWins)
                    .frame(width: barWidth)

                valueCell(home.main, sub: home.sub, highlight: homeWins)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 横条固定宽度，保证左右两列数值区等宽对齐
    private var barWidth: CGFloat { 108 }

    private var awayRatio: CGFloat {
        guard let a = item.awayVal, let h = item.homeVal else { return 0.5 }
        let total = a + h
        guard total > 0 else { return 0.5 }
        return CGFloat(a / total)
    }

    /// 数值 + 括号补充（命中-出手），左右镜像排列
    private func valueCell(_ main: String, sub: String?, highlight: Bool) -> some View {
        HStack(spacing: 6) {
            if let sub {
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Text(main)
                .font(.statNumber(18, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(highlight ? Color.primary : Color.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// 单条对比横条：客队（左，斜纹）与主队（右）拼成同一条，不再上下分两段
private struct CompareBar: View {
    let awayRatio: CGFloat
    let awayWins: Bool
    let homeWins: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let awayW = max(2, min(w - 2, w * awayRatio))
            HStack(spacing: 2) {
                Capsule()
                    .fill(awayWins ? Color.accentColor : Color.accentColor.opacity(0.4))
                    .frame(width: awayW)
                Capsule()
                    .fill(homeWins ? Color.accentColor : Color.accentColor.opacity(0.4))
            }
        }
        .frame(height: 12)
    }
}

// MARK: - 球员技术统计（boxscore）

/// 按主客队分栏展示。每个球员一张卡片，头像/姓名/数据都放大到能一眼看清。
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
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "球员技术统计")

            Picker("", selection: $side) {
                Text(awayTeamName ?? "客队").tag(Side.away)
                Text(homeTeamName ?? "主队").tag(Side.home)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if players.isEmpty {
                Text("\(currentTeamName) 暂无球员数据")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(players) { entry in
                        if let stats = entry.stats {
                            playerCard(stats: stats, tags: entry.tagInfoList ?? [])
                        }
                    }
                }
            }

            if !boxscore.officials.isEmpty {
                Text("裁判：" + boxscore.officials.compactMap { $0.stats?.name }.joined(separator: "、"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .systemCard()
    }

    private func playerCard(stats: PlayerMatchStats, tags: [PlayerTag]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                RemoteImage(urlString: stats.photo ?? stats.logoUrl,
                            width: 64, height: 64, cornerRadius: 10, contentMode: .fill)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if stats.isStarter {
                            Text("首发")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor, in: .rect(cornerRadius: 4))
                        }
                        Text(stats.name ?? "")
                            .font(.system(size: 18, weight: .bold))
                            .lineLimit(1)
                        if stats.isOnCourt {
                            Image(systemName: "figure.basketball")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.live)
                        }
                    }
                    HStack(spacing: 6) {
                        if let pos = stats.position, !pos.isEmpty { Text(pos) }
                        Text("背号 \(stats.number ?? "-")")
                        if let pm = stats.plusMinus?.raw, !pm.isEmpty, pm != "-" {
                            Text("正负 \(pm)")
                                .foregroundStyle(pm.hasPrefix("-") ? Theme.loss : Theme.win)
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    if !tags.isEmpty {
                        Text(tags.compactMap(\.text).joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
            }

            if stats.didNotPlay {
                Text("未出战")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: Theme.tileRadius))
            } else {
                // 7 项数据自适应铺开，窄屏折行成两行而不是挤成一排小字
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 74), spacing: 6)],
                    spacing: 6
                ) {
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
        .padding(12)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: Theme.tileRadius))
    }

    private func statCell(_ title: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.statNumber(17, weight: highlight ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(highlight ? Color.accentColor : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.raisedBackground.opacity(0.6), in: .rect(cornerRadius: 8))
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
                .font(.system(size: 18, weight: .semibold))
            Text(detail)
                .font(.system(size: 14))
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
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(play.event ?? "")
                                    .font(.system(size: 15))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(play.vs ?? "")
                                    .font(.statNumber(16, weight: .semibold))
                                    .monospacedDigit()
                                if let t = play.left_time, t != "00" {
                                    Text(t)
                                        .font(.system(size: 12))
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
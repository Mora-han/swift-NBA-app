import SwiftUI
import NBAKit

/// 战绩页：东西部排名（战绩/胜率/连胜/交手）+ 全联赛球队指标榜
struct StandingsView: View {
    @State private var model = StandingsModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("战绩")
                .inlineNavigationTitle()
                .refreshable { await model.reload(force: true) }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await model.reload(force: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
        }
        .task { await model.start() }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.standings == nil {
            LoadingBlock()
        } else if let error = model.errorMessage, model.standings == nil {
            FailureBlock(message: error) { Task { await model.start(force: true) } }
        } else if let root = model.standings {
            ScrollView {
                VStack(spacing: 16) {
                    // 赛季：可回溯历年
                    Picker("赛季", selection: $model.season) {
                        ForEach(model.seasonOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.gutter)

                    Picker("赛季阶段", selection: $model.stage) {
                        Text("常规赛").tag("REGULAR")
                        Text("季后赛").tag("PLAYOFF")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.gutter)

                    // iPad / 宽屏：东西部并排，减少纵向滚动
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            conferenceSection(title: "东部联盟", rows: root.east)
                            conferenceSection(title: "西部联盟", rows: root.west)
                        }
                        .frame(minWidth: 1090)
                        VStack(spacing: 16) {
                            conferenceSection(title: "东部联盟", rows: root.east)
                            conferenceSection(title: "西部联盟", rows: root.west)
                        }
                    }

                    if !model.metricNames.isEmpty {
                        teamStatRankSection
                    }
                }
                .padding(.bottom, 24)
                .pageWidth(1400)
            }
        }
    }

    private func conferenceSection(title: String, rows: [TeamStanding]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
            SectionHeader(title: title,
                          subtitle: subtitle(for: rows))
                .padding(.horizontal, Theme.gutter)

            if rows.isEmpty {
                Text("暂无数据")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ScrollView(.horizontal) {
                    LazyVStack(spacing: 0) {
                        headerRow
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            NavigationLink {
                                TeamDetailView(teamId: row.teamId ?? "")
                            } label: {
                                standingRow(row)
                            }
                            .buttonStyle(.plain)

                            if index < rows.count - 1 {
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                    .frame(minWidth: 520, maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .cardSurface()
            }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 标题副文案：赛季已开始显示赛季号，未开始时明确说明
    private func subtitle(for rows: [TeamStanding]) -> String? {
        let season = model.standings?.season ?? model.season
        let started = rows.contains { ($0.won ?? 0) + ($0.lost ?? 0) > 0 }
        if started { return "赛季 \(season)" }
        return season.isEmpty ? "赛季尚未开始" : "\(season) · 尚未开赛"
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("球队").frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            Text("战绩").frame(width: 58, alignment: .trailing)
            Text("胜率").frame(width: 56, alignment: .trailing)
            Text("主场").frame(width: 56, alignment: .trailing)
            Text("客场").frame(width: 56, alignment: .trailing)
            Text("近况").frame(width: 46, alignment: .trailing)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.4))
    }

    private func standingRow(_ row: TeamStanding) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: 10) {
                Text("\(row.rank ?? 0)")
                    .font(.statNumber(16, weight: .semibold))
                    .foregroundStyle(playoffColor(row.rank))
                    .frame(width: 22, alignment: .trailing)

                RemoteImage(urlString: row.logoLink, width: 38, height: 38)
                    .padding(.trailing, 2)

                Text(row.teamName ?? "")
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)
                    .layoutPriority(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.record)
                .font(.statNumber(16, weight: .semibold))
                .monospacedDigit()
                .frame(width: 58, alignment: .trailing)

            Text(row.winRate?.raw ?? "-")
                .font(.statNumber(14))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)

            Text(halfRecord(row.homeWins, row.homeLosses))
                .font(.statNumber(14))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)

            Text(halfRecord(row.awayWins, row.awayLosses))
                .font(.statNumber(14))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)

            StreakBadge(streak: row.strk?.raw)
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(.rect)
    }

    private func halfRecord(_ wins: Int?, _ losses: Int?) -> String {
        guard let wins, let losses else { return "-" }
        return "\(wins)-\(losses)"
    }

    /// 季后赛线（前 8 名）标金色；rank=0 表示赛季未开始，保持中性色
    private func playoffColor(_ rank: Int?) -> Color {
        guard let rank, rank > 0 else { return .secondary }
        return rank <= 8 ? .orange : .secondary
    }

    /// 赛季未开赛时不展示「未开始」的 0-0 排行，改为提示
    private var hasStarted: Bool {
        guard let root = model.standings else { return false }
        return (root.east + root.west).contains { ($0.won ?? 0) + ($0.lost ?? 0) > 0 }
    }

    // MARK: 球队指标榜

    @ViewBuilder
    private var teamStatRankSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "球队数据榜")
                .padding(.horizontal, Theme.gutter)

            VStack(spacing: 12) {
                Picker("赛季", selection: $model.rankSeason) {
                    ForEach(model.seasonOptions, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)

                MetricPicker(title: "指标", items: model.metricNames, selection: $model.metricName)

                if model.rankRows.isEmpty {
                    LoadingBlock()
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.rankRows.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: 10) {
                                Text("\(row.rank ?? index + 1)")
                                    .font(.statNumber(15, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 26, alignment: .trailing)

                                RemoteImage(urlString: row.logoUrl, width: 34, height: 34)

                                Text(row.teamName ?? "")
                                    .font(.system(size: 16))
                                    .lineLimit(1)

                                Spacer()

                                Text(row.value?.raw ?? "-")
                                    .font(.statNumber(18, weight: .semibold))
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) { Divider() }
                        }
                    }
                    .cardSurface()
                    .clipShape(.rect(cornerRadius: Theme.cardRadius))
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }
}

// MARK: - 模型

@MainActor
@Observable
final class StandingsModel {
    private(set) var standings: StandingRoot?
    private(set) var rankRows: [TeamRankRow] = []
    private(set) var metricNames: [String] = []
    private(set) var seasonOptions: [String] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    /// 战绩页选中的赛季（可回溯历年）
    var season = "" { didSet { Task { await loadStandings() } } }
    var stage = "REGULAR" { didSet { Task { await loadStandings() } } }
    /// 球队数据榜的赛季（与战绩独立）
    var rankSeason = "" { didSet { Task { await loadRank() } } }
    var metricName = "" { didSet { Task { await loadRank() } } }

    private let client = HupuClient.shared
    private var rankTask: Task<Void, Never>?

    func start(force: Bool = false) async {
        if standings == nil || force {
            await loadStandings()
            await loadMetrics()
        }
        isLoading = false
    }

    func reload(force: Bool) async {
        await loadStandings()
        await loadRank()
        isLoading = false
    }

    private func loadStandings() async {
        guard !season.isEmpty else { return }
        do {
            let root: StandingRoot = try await client.fetch(
                .teamStanding(stage: stage, season: season),
                ttl: HupuConfig.TTL.standings)
            standings = root
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadMetrics() async {
        guard let metrics: [TeamMetric] = try? await client.fetch(
            .teamSeasonStatsAllRank, ttl: HupuConfig.TTL.rank), !metrics.isEmpty
        else { return }
        // 只展示有完整 30 队榜单的指标（实测 pace 无数据）
        metricNames = metrics.compactMap { $0.name }.filter { Self.rankType(for: $0) != nil }
        if metricName.isEmpty { metricName = metricNames.first ?? "" }

        let current = await SeasonProvider.shared.currentSeason()
        seasonOptions = Self.seasonRange(from: current, count: 10)
        if season.isEmpty { season = current }
        if rankSeason.isEmpty { rankSeason = current }
        await loadRank()
    }

    private func loadRank() async {
        guard !metricName.isEmpty, !rankSeason.isEmpty else { return }
        rankTask?.cancel()
        rankTask = Task {
            // 只支持 ptsAvg 这类球队指标 rankType，用名称映射
            guard let rankType = Self.rankType(for: metricName) else { return }
            let result: TeamMetricRank? = try? await client.fetch(
                .teamSeasonStatsRank(rankType: rankType, season: rankSeason),
                ttl: HupuConfig.TTL.rank)
            guard !Task.isCancelled else { return }
            rankRows = result?.rows ?? []
        }
        await rankTask?.value
    }

    /// 从当前赛季往前数 count 个赛季（含当前）
    static func seasonRange(from current: String, count: Int) -> [String] {
        (0..<count).compactMap { SeasonUtility.offset(current, by: -$0) }
    }

    /// teamSeasonStatsAllRank 指标名 ↔ teamSeasonStatsRank 的 rankType（实测逐个验证，pace 无完整榜）
    static func rankType(for metricName: String) -> String? {
        switch metricName {
        case "得分": "ptsAvg"
        case "失分": "opptsAvg"
        case "篮板": "rebAvg"
        case "前场篮板": "orebAvg"
        case "后场篮板": "drebAvg"
        case "助攻": "astAvg"
        case "抢断": "stlAvg"
        case "盖帽": "blkAvg"
        case "失误": "toAvg"
        case "罚球": "ftaAvg"
        case "罚球命中数": "ftmAvg"
        case "三分": "tgaAvg"
        case "场均三分命中": "tgmAvg"
        case "三分总命中数": "tgm"
        case "投篮命中率": "fgp"
        case "三分命中率": "tpp"
        case "罚球命中率": "ftp"
        case "篮板率": "rebp"
        case "助攻率": "astp"
        case "进攻效率": "ortg"
        case "防守效率": "drtg"
        case "净效率": "nrtg"
        case "犯规": "pfAvg"
        case "利用失误得分": "ptsOffTovAvg"
        case "内线得分": "ptsInPaintsAvg"
        case "二次进攻得分": "ptsSecondChanceAvg"
        case "快攻得分": "ptsFastBreakAvg"
        case "替补得分": "benchPtsAvg"
        default: nil
        }
    }

}
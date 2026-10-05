import SwiftUI
import NBAKit

/// 球队列表：卡片网格 + 战绩信息（队徽取自 standings，含 teams.json 静态兜底）
struct TeamsView: View {
    @State private var search = ""
    @State private var store = TeamLogoStore()

    private func sorted(_ teams: [LeagueTeam]) -> [LeagueTeam] {
        let rank = Dictionary(uniqueKeysWithValues: store.order.enumerated().map { ($1, $0) })
        return teams.sorted { (rank[$0.teamId] ?? 99) < (rank[$1.teamId] ?? 99) }
    }

    private var east: [LeagueTeam] { sorted(TeamRegistry.all.filter { TeamConference.all[$0.teamId] == "E" }) }
    private var west: [LeagueTeam] { sorted(TeamRegistry.all.filter { TeamConference.all[$0.teamId] == "W" }) }

    private var filteredEast: [LeagueTeam] {
        search.isEmpty ? east : east.filter { $0.name.contains(search) || ($0.abbr ?? "").contains(search) }
    }

    private var filteredWest: [LeagueTeam] {
        search.isEmpty ? west : west.filter { $0.name.contains(search) || ($0.abbr ?? "").contains(search) }
    }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if !filteredEast.isEmpty {
                        conferenceGrid(title: "东部联盟", teams: filteredEast)
                    }
                    if !filteredWest.isEmpty {
                        conferenceGrid(title: "西部联盟", teams: filteredWest)
                    }
                    if filteredEast.isEmpty && filteredWest.isEmpty {
                        EmptyBlock(title: "未找到球队", message: search)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 12)
                .pageWidth(1400)
            }
            .navigationTitle("球队")
            .inlineNavigationTitle()
            .searchable(text: $search, prompt: "搜索球队")
        }
        .task { await store.load() }
    }

    private func conferenceGrid(title: String, teams: [LeagueTeam]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, subtitle: "\(teams.count) 支球队")
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(teams) { team in
                    NavigationLink {
                        TeamDetailView(teamId: team.teamId, preview: team)
                    } label: {
                        TeamCard(team: team, logo: store.logo(for: team.teamId))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// 球队卡片：只保留队徽与队名（战绩/排名在「战绩」页呈现，这里不重复）
struct TeamCard: View {
    let team: LeagueTeam
    var logo: String?

    var body: some View {
        VStack(spacing: 12) {
            RemoteImage(urlString: logo, width: 72, height: 72)

            Text(team.name)
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let abbr = team.abbr {
                Text(abbr)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 12)
        .cardSurface()
    }
}

// MARK: - 球队详情

struct TeamDetailView: View {
    let teamId: String
    var preview: LeagueTeam?

    @State private var model: TeamDetailModel

    init(teamId: String, preview: LeagueTeam? = nil) {
        self.teamId = teamId
        self.preview = preview
        _model = State(initialValue: TeamDetailModel(teamId: teamId, preview: preview))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let info = model.info {
                    header(info)
                }

                if let error = model.errorMessage, model.info == nil {
                    FailureBlock(message: error) { Task { await model.load() } }
                } else if model.info == nil {
                    LoadingBlock()
                }

                if let stats = model.seasonStats, !stats.metrics().isEmpty {
                    seasonStatsSection(stats)
                }

                if !model.roster.isEmpty {
                    rosterSection
                }

                if !model.awards.isEmpty {
                    honorsSection
                }

                if !model.retiredPlayers.isEmpty {
                    retiredSection
                }

                if !model.historyStages.isEmpty {
                    historySection(model.historyStages)
                    seasonRecordsSection
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 12)
        }
        .background(Theme.groupedBackground)
        .navigationTitle(model.info?.name ?? preview?.name ?? "球队")
        .inlineNavigationTitle()
        .task { await model.start() }
        .refreshable { await model.refreshAll() }
    }

    private func header(_ info: TeamBasicInfo) -> some View {
        VStack(spacing: 12) {
            RemoteImage(urlString: info.logoLink, width: 76, height: 76)

            VStack(spacing: 3) {
                Text(info.full_name ?? info.name ?? "")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 6) {
                    if let conf = info.conferenceName {
                        Text(conf)
                    }
                    if let div = info.cn_division {
                        Text(div)
                    }
                    if let year = info.found_year {
                        Text("\(year) 年建队")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let intro = info.intro, !intro.isEmpty {
                Text(intro)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .systemCard()
        .background {
            LinearGradient(
                colors: [Color(hex: info.dayColor).opacity(0.28),
                         Color(hex: info.nightColor).opacity(0.18)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        }
    }

    private func seasonStatsSection(_ stats: TeamSeasonStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "赛季数据", subtitle: stats.season)
            let metrics = stats.metrics()
            StatGrid(items: metrics.map { metric in
                StatGrid.Item(id: metric.id,
                              title: metric.cnName ?? metric.name ?? "",
                              value: metric.quota?.raw ?? "-",
                              rank: metric.rank)
            })
        }
        .systemCard()
    }

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "球队阵容")

            LazyVStack(spacing: 0) {
                ForEach(Array(model.roster.enumerated()), id: \.element.id) { index, player in
                    NavigationLink {
                        PlayerDetailView(playerId: player.playerId ?? "",
                                         previewName: player.player_name,
                                         previewPhoto: player.player_header_big)
                    } label: {
                        RosterRow(player: player)
                    }
                    .buttonStyle(.plain)

                    if index < model.roster.count - 1 {
                        Divider().padding(.vertical, 1)
                    }
                }
            }
            .cardSurface()
        }
        .systemCard()
    }

    private var honorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "球队荣誉")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(model.awards) { award in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(award.cnTeamAwardType ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(award.seasons.count) 次")
                            .font(.statNumber(20, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(award.seasons.suffix(3).joined(separator: "、"))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Theme.tileRadius))
                }
            }
        }
        .systemCard()
    }

    private var retiredSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "退役球衣")

            LazyVStack(spacing: 0) {
                ForEach(Array(model.retiredPlayers.enumerated()), id: \.element.id) { index, jersey in
                    HStack(spacing: 10) {
                        Text(jersey.shirt_number?.raw ?? "")
                            .font(.scoreNumber(18))
                            .foregroundStyle(Color(hex: model.retiredColor).opacity(0.9))
                            .frame(width: 34)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(jersey.player_name ?? "")
                                .font(.subheadline.weight(.medium))
                            Text("\(jersey.positionZhName ?? "") · \(jersey.careertime?.raw ?? "")–\(jersey.retiredtime?.raw ?? "")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(jersey.roles.joined(separator: "/"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    if index < model.retiredPlayers.count - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            .cardSurface()
        }
        .systemCard()
    }

    /// 球队历史战绩：逐赛季回看该队的分区排名与胜负场次
    private var seasonRecordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "历史战绩",
                          subtitle: "\(model.recordSeasons.count) 个赛季")

            if model.recordsLoading && model.records.isEmpty {
                LoadingBlock()
            } else if model.records.isEmpty {
                EmptyBlock(title: "暂无历史战绩",
                           message: "虎扑战绩数据自 2004-05 赛季起")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.records.enumerated()), id: \.element.season) { index, record in
                        HStack(spacing: 10) {
                            Text(record.season)
                                .font(.system(size: 15, weight: .medium))
                                .monospacedDigit()
                                .frame(width: 92, alignment: .leading)

                            Text(record.conference)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(record.isEast ? Color.accentColor : .orange, in: .capsule)
                                .frame(width: 52, alignment: .leading)

                            Text("第 \(record.rank) 名")
                                .font(.statNumber(15, weight: .semibold))
                                .foregroundStyle(record.rank > 0 && record.rank <= 8 ? .orange : .secondary)
                                .frame(width: 68, alignment: .leading)

                            Spacer(minLength: 8)

                            Text(record.record.isEmpty ? "-" : record.record)
                                .font(.statNumber(16, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)

                            if let rate = record.winRate, !rate.isEmpty {
                                Text(rate)
                                    .font(.statNumber(13))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 54, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)

                        if index < model.records.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .cardSurface()
            }
        }
        .systemCard()
    }

    private func historySection(_ stages: [HistoryStage]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "队史纪录保持者", subtitle: "队史各数据榜首")

            ForEach(stages) { stage in
                VStack(alignment: .leading, spacing: 8) {
                    Text(stage.competitionStageName ?? stage.competitionName ?? "")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    ForEach(stage.metrics.prefix(6)) { metric in
                        if let top = metric.entries.first {
                            NavigationLink {
                                PlayerDetailView(playerId: top.playerId ?? "",
                                                 previewName: top.playerName,
                                                 previewPhoto: top.bigPhoto)
                            } label: {
                                HStack(spacing: 10) {
                                    RemoteImage(urlString: top.photo, width: 30, height: 30, cornerRadius: 6)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(top.playerName ?? "")
                                            .font(.subheadline.weight(.medium))
                                        Text(metric.chineseName ?? "")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(top.value?.raw ?? "-")
                                        .font(.statNumber(15, weight: .semibold))
                                        .monospacedDigit()
                                }
                                .padding(.vertical, 5)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .systemCard()
    }
}

// MARK: - 阵容行

private struct RosterRow: View {
    let player: RosterPlayer

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Text(player.number ?? "")
                    .font(.statNumber(18, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)

                RemoteImage(urlString: player.player_header_big ?? player.player_header,
                            width: 62, height: 62, cornerRadius: 10, contentMode: .fill)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(player.player_name ?? "")
                            .font(.system(size: 19, weight: .semibold))
                            .lineLimit(1)
                        if player.isInjured {
                            Image(systemName: "cross.case.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.loss)
                        }
                    }
                    HStack(spacing: 8) {
                        if let pos = player.position, !pos.isEmpty {
                            Text(pos)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        if let mins = player.min?.raw, !mins.isEmpty {
                            Text("均 \(mins) 分钟")
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 6)

                if let salary = player.salary_str?.raw, !salary.isEmpty {
                    Text(salary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // 得分 / 篮板 / 助攻 三个核心数据放大成独立格子
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                statTile("得分", player.pts?.raw, .primary)
                statTile("篮板", player.reb?.raw, .primary)
                statTile("助攻", player.asts?.raw, .primary)
            }
        }
        .padding(12)
        .contentShape(.rect)
    }

    private func statTile(_ title: String, _ value: String?, _ accent: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text((value?.isEmpty == false) ? value! : "—")
                .font(.statNumber(20, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Theme.raisedBackground.opacity(0.65), in: .rect(cornerRadius: Theme.tileRadius))
    }
}

// MARK: - 分区映射（teams.json 不含分区，按 teamId 固定映射）

enum TeamConference {
    private static let eastIDs: Set<String> = [
        "1901000000501281", // 76人
        "1901000000501286", "1901000000501263", // 公牛 / 凯尔特人
        "1901000000501283", "1901000000501273", // 奇才 / 尼克斯
        "1901000000501333", "1901000000501267", // 快船 / 热火
        "1901000000501329", "1901000000501336", // 雷霆 / 篮网
        "1901000000501292", "1901000000501290", // 步行者 / 活塞
        "1901000000501301", "1901000000501325", // 掘金 / 开拓者
        "1901000000501288", "1901000000501315", // 骑士 / 森林狼
        "1901000000501323", "1901000000501298", // 湖人 / 猛龙
    ]

    static let all: [String: String] = {
        var map: [String: String] = [:]
        TeamRegistry.all.forEach { map[$0.teamId] = "W" }
        eastIDs.forEach { map[$0] = "E" }
        return map
    }()
}

// MARK: - 模型

@MainActor
@Observable
final class TeamDetailModel {
    private(set) var info: TeamBasicInfo?
    private(set) var roster: [RosterPlayer] = []
    private(set) var seasonStats: TeamSeasonStats?
    private(set) var awards: [TeamAward] = []
    private(set) var retiredPlayers: [RetiredJersey] = []
    private(set) var retiredColor: String?
    private(set) var historyStages: [HistoryStage] = []
    private(set) var errorMessage: String?

    private(set) var records: [TeamSeasonRecord] = []
    private(set) var recordsLoading = false
    private(set) var recordSeasons: [String] = []

    private let teamId: String
    private let client = HupuClient.shared

    init(teamId: String, preview: LeagueTeam?) {
        self.teamId = teamId
    }

    func start() async {
        if info == nil { await load() }
        await loadRecords()
    }

    func refreshAll() async {
        records = []
        await load()
        await loadRecords()
    }

    /// 历史战绩：逐赛季请求战绩接口，从响应里挑出当前这支球队。
    /// 虎扑战绩接口最早只到 2004-05 赛季，更早的赛季返回空。
    private func loadRecords() async {
        guard records.isEmpty else { return }
        let current = await SeasonProvider.shared.currentSeason()
        let seasons = (0..<22).compactMap { SeasonUtility.offset(current, by: -$0) }
        guard !seasons.isEmpty else { return }
        recordSeasons = seasons

        recordsLoading = true
        defer { recordsLoading = false }

        var found: [TeamSeasonRecord] = []
        for season in seasons {
            let root: StandingRoot? = try? await client.fetch(
                .teamStanding(stage: "REGULAR", season: season), ttl: HupuConfig.TTL.standings)
            if let record = Self.record(for: teamId, in: root, season: season) {
                found.append(record)
            }
        }
        records = found
    }

    private static func record(for teamId: String, in root: StandingRoot?, season: String) -> TeamSeasonRecord? {
        guard let root else { return nil }
        let east = root.east.contains { $0.teamId == teamId }
        let row = (east ? root.east : root.west).first { $0.teamId == teamId }
        guard let row, (row.won ?? 0) + (row.lost ?? 0) > 0 else { return nil }
        return TeamSeasonRecord(season: season,
                                conference: east ? "东部" : "西部",
                                isEast: east,
                                rank: row.rank ?? 0,
                                record: "\(row.won ?? 0)-\(row.lost ?? 0)",
                                winRate: row.winRate?.raw)
    }

    func load(force: Bool = false) async {
        let ttl = force ? nil : HupuConfig.TTL.roster

        async let basic: TeamBasicInfo? = try? await client.fetch(
            .teamBasicInfo(teamId: teamId), ttl: ttl)
        async let rosterRoot: TeamRosterRoot? = try? await client.fetch(
            .teamPlayerList(teamId: teamId), ttl: ttl)
        async let awardRoot: TeamAwardRoot? = try? await client.fetch(
            .teamAwardList(teamId: teamId), ttl: ttl)
        async let retiredRoot: RetiredRoot? = try? await client.fetch(
            .teamShirtRetired(teamId: teamId), ttl: ttl)
        async let historyRoot: TeamHistoryRankRoot? = try? await client.fetch(
            .teamHistoryPlayerStatsRank(teamId: teamId), ttl: ttl)

        let season = await SeasonProvider.shared.currentSeason()
        let stats: TeamSeasonStats? = try? await client.fetch(
            .teamSeasonStats(teamId: teamId, season: season), ttl: ttl)

        let (b, r, a, ret, h, s) = await (basic, rosterRoot, awardRoot, retiredRoot, historyRoot, stats)

        if b == nil && r == nil && a == nil {
            errorMessage = "无法获取球队信息，请检查网络后重试"
        } else {
            errorMessage = nil
        }
        info = b
        roster = r?.players ?? []
        awards = (a?.awards ?? []).sorted { $0.seasons.count > $1.seasons.count }
        retiredPlayers = ret?.players ?? []
        retiredColor = ret?.shirtRetiredColors?.shirtColor
        historyStages = h?.stages ?? []
        seasonStats = s
    }
}
/// 球队某一赛季的常规赛战绩
struct TeamSeasonRecord: Hashable {
    let season: String        // "2023-2024"
    let conference: String    // 东部 / 西部
    let isEast: Bool
    let rank: Int
    let record: String        // "48-34"
    let winRate: String?      // "58.5%"
}

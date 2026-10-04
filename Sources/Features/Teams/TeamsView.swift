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

    private let columns = [GridItem(.adaptive(minimum: 168), spacing: 12)]

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
                .readableWidth(1000)
            }
            .navigationTitle("球队")
            .searchable(text: $search, prompt: "搜索球队")
        }
        .task { await store.load() }
    }

    private func conferenceGrid(title: String, teams: [LeagueTeam]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, subtitle: "\(teams.count) 支球队")
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(teams) { team in
                    NavigationLink {
                        TeamDetailView(teamId: team.teamId, preview: team)
                    } label: {
                        TeamCard(team: team,
                                  logo: store.logo(for: team.teamId),
                                  standing: store.standing(for: team.teamId))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// 球队卡片：队徽 + 名称 + 战绩
struct TeamCard: View {
    let team: LeagueTeam
    var logo: String?
    var standing: TeamStanding?

    var body: some View {
        VStack(spacing: 10) {
            RemoteImage(urlString: logo, width: 56, height: 56)

            VStack(spacing: 2) {
                Text(team.name)
                    .font(.headline)
                    .lineLimit(1)
                if let abbr = team.abbr {
                    Text(abbr)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let st = standing {
                HStack(spacing: 8) {
                    Text("#\(st.rank ?? 0)")
                        .font(.statNumber(13, weight: .bold))
                        .foregroundStyle(rank > 0 && rank <= 8 ? .orange : .secondary)
                    Text(st.record)
                        .font(.statNumber(14, weight: .semibold))
                        .monospacedDigit()
                    if let rate = st.winRate?.raw, !rate.isEmpty {
                        Text(rate)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    StreakBadge(streak: st.strk?.raw)
                }
                .padding(.top, 2)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .cardSurface()
    }

    private var rank: Int { standing?.rank ?? 0 }
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
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 12)
        }
        .background(Theme.groupedBackground)
        .navigationTitle(model.info?.name ?? preview?.name ?? "球队")
        .inlineNavigationTitle()
        .task { await model.start() }
        .refreshable { await model.load(force: true) }
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
            }, columns: 4)
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
                        Divider().padding(.leading, 60)
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
        HStack(spacing: 10) {
            Text(player.number ?? "")
                .font(.statNumber(13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            RemoteImage(urlString: player.player_header, width: 34, height: 34, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 1) {
                nameLine
                statLine
            }

            Spacer(minLength: 6)

            if let salary = player.salary_str?.raw, !salary.isEmpty {
                Text(salary)
                    .font(.statNumber(11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(.rect)
    }

    private var nameLine: some View {
        HStack(spacing: 4) {
            Text(player.player_name ?? "")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            if player.isInjured {
                Image(systemName: "cross.case.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.loss)
            }
        }
    }

    private var statLine: some View {
        HStack(spacing: 6) {
            if let pos = player.position {
                Text(pos)
            }
            Text("均 " + (player.min?.raw ?? "-") + " 分")
            Text((player.pts?.raw ?? "-") + " 分")
            Text((player.reb?.raw ?? "-") + " 板")
            Text((player.asts?.raw ?? "-") + " 助")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
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

    private let teamId: String
    private let client = HupuClient.shared

    init(teamId: String, preview: LeagueTeam?) {
        self.teamId = teamId
    }

    func start() async {
        if info == nil { await load() }
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
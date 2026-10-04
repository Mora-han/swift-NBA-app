import SwiftUI
import NBAKit

/// 球员个人页：资料 / 生涯数据 / 逐赛季 / 逐场 / 荣誉
struct PlayerDetailView: View {
    let playerId: String
    var previewName: String?
    var previewPhoto: String?

    @State private var model: PlayerDetailModel
    @State private var selectedTab: DetailTab = .season

    init(playerId: String, previewName: String? = nil, previewPhoto: String? = nil) {
        self.playerId = playerId
        self.previewName = previewName
        self.previewPhoto = previewPhoto
        _model = State(initialValue: PlayerDetailModel(playerId: playerId,
                                                      previewName: previewName,
                                                      previewPhoto: previewPhoto))
    }

    enum DetailTab: String, CaseIterable {
        case season = "赛季"
        case career = "生涯"
        case games = "逐场"
        case awards = "荣誉"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let info = model.info {
                    profileCard(info)
                } else if model.isLoading {
                    LoadingBlock()
                } else if let error = model.errorMessage {
                    FailureBlock(message: error) { Task { await model.load(force: true) } }
                }

                if model.info != nil {
                    Picker("", selection: $selectedTab) {
                        ForEach(DetailTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.gutter)

                    switch selectedTab {
                    case .season: seasonTab
                    case .career: careerTab
                    case .games: gameLogTab
                    case .awards: awardsTab
                    }
                }
            }
            .padding(.vertical, 12)
            .readableWidth(820)
        }
        .pageBackground()
        .navigationTitle(model.info?.name ?? previewName ?? "球员")
        .inlineNavigationTitle()
        .task { await model.start() }
        .refreshable { await model.load(force: true) }
    }

    // MARK: 资料卡

    private func profileCard(_ info: PlayerInfo) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                RemoteImage(urlString: info.big_photo ?? info.photo,
                            width: 96, height: 96, cornerRadius: 12, contentMode: .fill)

                VStack(alignment: .leading, spacing: 6) {
                    Text(info.name ?? "")
                        .font(.title2.weight(.bold))
                    if let eng = info.eng_name {
                        Text(eng)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let nick = info.nick, !nick.isEmpty {
                        Text("「\(nick)」")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        if let num = info.number?.raw, !num.isEmpty {
                            statChip("#\(num)")
                        }
                        if let pos = info.position { statChip(pos) }
                        if let h = info.heightText { statChip(h) }
                    }
                }
                Spacer(minLength: 0)
            }

            Divider()

            VStack(spacing: 0) {
                if let team = info.teamName, !team.isEmpty {
                    InfoRow(label: "现效力", value: team)
                }
                if let country = info.country, !country.isEmpty {
                    InfoRow(label: "国籍", value: country)
                }
                if let birth = info.birth_date, !birth.isEmpty {
                    InfoRow(label: "生日", value: [birth, info.age.map { "\($0.raw) 岁" } ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                }
                if let weight = info.weight?.raw, !weight.isEmpty {
                    InfoRow(label: "体重", value: "\(weight) kg")
                }
                if let college = info.college_school, !college.isEmpty {
                    InfoRow(label: "大学", value: college)
                }
                if let year = info.draft_year {
                    InfoRow(label: "选秀", value: draftText(info))
                }
                if let salary = info.salary, salary > 0 {
                    InfoRow(label: "薪资",
                            value: Self.money(salary) + (info.salaryRank.map { "（联盟第 \($0)）" } ?? ""))
                }
                if let first = info.nba_first_year {
                    InfoRow(label: "NBA 首秀", value: "\(first) 年")
                }
            }

            if let contract = info.contractDetails, !contract.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("合同")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(contract)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: Theme.tileRadius))
            }
        }
        .systemCard()
        .background {
            LinearGradient(
                colors: [Color(hex: info.teamDayColor).opacity(0.24),
                         Color(hex: info.teamNightColor).opacity(0.16)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        }
    }

    private func statChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: .capsule)
    }

    private func draftText(_ info: PlayerInfo) -> String {
        var parts: [String] = ["\(info.draft_year ?? 0) 年"]
        if let round = info.draftRound, let pick = info.draftPick {
            parts.append("第 \(round) 轮第 \(pick) 顺位")
        }
        return parts.joined(separator: " · ")
    }

    static func money(_ value: Double) -> String {
        if value >= 1_0000_0000 {
            return String(format: "%.2f 亿美元", value / 1_0000_0000)
        }
        if value >= 1_0000 {
            return String(format: "%.0f 万美元", value / 1_0000)
        }
        return String(format: "%.0f 美元", value)
    }

    // MARK: 赛季

    @ViewBuilder
    private var seasonTab: some View {
        VStack(spacing: 12) {
            HStack {
                SeasonPicker(seasons: model.seasons.isEmpty ? [model.season] : model.seasons,
                             selection: $model.season)
                Spacer()
                Picker("", selection: $model.stage) {
                    Text("常规赛").tag("REGULAR")
                    Text("季后赛").tag("PLAYOFF")
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            .padding(.horizontal, Theme.gutter)

            if model.isSeasonLoading {
                LoadingBlock()
            } else if let groups = model.seasonGroups, !groups.isEmpty {
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: group.title)
                        StatGrid(items: group.metrics.map { metric in
                            StatGrid.Item(id: metric.id,
                                          title: metric.cnName ?? metric.name ?? "",
                                          value: metric.quota?.raw ?? "-",
                                          rank: metric.rank)
                        }, columns: 4)
                    }
                    .systemCard()
                }
            } else {
                EmptyBlock(title: "暂无赛季数据", message: model.season)
                    .padding(.top, 20)
            }
        }
    }

    // MARK: 生涯

    @ViewBuilder
    private var careerTab: some View {
        VStack(spacing: 12) {
            if model.isCareerLoading {
                LoadingBlock()
            } else if !model.careerStats.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "生涯累计", subtitle: "常规赛")
                    StatGrid(items: model.careerStats.map {
                        StatGrid.Item(id: $0.id, title: $0.cnName ?? $0.name ?? "",
                                      value: $0.quota?.raw ?? "-", rank: $0.rank)
                    }, columns: 4)
                }
                .systemCard()

                if !model.careerMax.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "生涯最高")
                        StatGrid(items: model.careerMax.map {
                            StatGrid.Item(id: $0.id, title: $0.cnName ?? $0.name ?? "",
                                          value: $0.quota?.raw ?? "-", rank: nil)
                        }, columns: 4)
                    }
                    .systemCard()
                }

                if let table = model.careerTable {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "逐赛季数据")
                        StatsTable(headers: table.headers,
                                   rows: table.rows.map { row in
                                       StatsRowData(id: row.values.joined(separator: "|"),
                                                    name: row.values.first ?? "-",
                                                    photo: nil,
                                                    values: Array(row.values.dropFirst()))
                                   })
                    }
                    .systemCard()
                }
            } else {
                EmptyBlock(title: "暂无生涯数据")
                    .padding(.top, 20)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    // MARK: 逐场

    @ViewBuilder
    private var gameLogTab: some View {
        VStack(spacing: 12) {
            HStack {
                SeasonPicker(seasons: model.seasons.isEmpty ? [model.season] : model.seasons,
                             selection: $model.season)
                Spacer()
            }
            .padding(.horizontal, Theme.gutter)

            if model.isGameLogLoading {
                LoadingBlock()
            } else if let table = model.gameLog, !table.rows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "逐场数据", subtitle: model.season)
                    StatsTable(headers: table.headers,
                               rows: table.rows.map { row in
                                   StatsRowData(id: "\(model.season)-\(row.values.joined(separator: "|"))",
                                                name: row.values.first ?? "-",
                                                photo: nil,
                                                values: Array(row.values.dropFirst()))
                               })
                }
                .systemCard()
            } else {
                EmptyBlock(title: "暂无逐场数据", message: "休赛期或该赛季暂无比赛记录")
                    .padding(.top, 20)
            }
        }
    }

    // MARK: 荣誉

    @ViewBuilder
    private var awardsTab: some View {
        VStack(spacing: 12) {
            if model.isAwardsLoading {
                LoadingBlock()
            } else if !model.awards.isEmpty {
                ForEach(model.awards) { award in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(award.awardDesc ?? "")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            Spacer()
                            Text("\(award.details.count) 次")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(award.details.prefix(12).map { detail in
                            [detail.season?.raw, detail.awardDate?.raw]
                                .compactMap { $0 }
                                .joined(separator: " ")
                        }.filter { !$0.isEmpty }.joined(separator: "、"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .systemCard()
                }
            } else {
                EmptyBlock(title: "暂无荣誉记录")
                    .padding(.top, 20)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

// MARK: - 模型

@MainActor
@Observable
final class PlayerDetailModel {
    private(set) var info: PlayerInfo?
    private(set) var seasons: [String] = []
    private(set) var seasonGroups: [(title: String, metrics: [Metric])]?
    private(set) var careerStats: [Metric] = []
    private(set) var careerMax: [Metric] = []
    private(set) var careerTable: StatTable?
    private(set) var gameLog: StatTable?
    private(set) var awards: [PlayerAward] = []
    private(set) var errorMessage: String?
    private(set) var isLoading = true
    private(set) var isSeasonLoading = true
    private(set) var isCareerLoading = true
    private(set) var isGameLogLoading = true
    private(set) var isAwardsLoading = true

    var season: String = "" {
        didSet {
            if !season.isEmpty, season != oldValue {
                Task { await loadSeason(); await loadGameLog() }
            }
        }
    }
    var stage = "REGULAR"

    private let playerId: String
    private let client = HupuClient.shared
    private var didLoad = false

    init(playerId: String, previewName: String?, previewPhoto: String?) {
        self.playerId = playerId
    }

    func start() async {
        guard !didLoad else { return }
        didLoad = true
        await load()
    }

    func load(force: Bool = false) async {
        let ttl = force ? nil : HupuConfig.TTL.roster

        async let infoTask: PlayerInfo? = try? await client.fetch(.playerInfo(playerId: playerId), ttl: ttl)
        async let seasonTask: LeagueSeasonRoot? = try? await client.fetch(.playerLeagueSeason(playerId: playerId), ttl: ttl)
        async let careerTask: PlayerCareerStatsRoot? = try? await client.fetch(.playerCareerStats(playerId: playerId), ttl: ttl)
        async let allSeasonTask: PlayerAllSeasonStatsRoot? = try? await client.fetch(.playerAllSeasonStats(playerId: playerId), ttl: ttl)
        async let awardTask: PlayerAwardRoot? = try? await client.fetch(.playerAwardList(playerId: playerId), ttl: ttl)

        let (i, s, c, a, aw) = await (infoTask, seasonTask, careerTask, allSeasonTask, awardTask)

        info = i
        errorMessage = i == nil ? "无法获取球员信息" : nil
        isLoading = false

        seasons = s?.seasons.first?.options ?? []
        if season.isEmpty {
            let fallback = await SeasonProvider.shared.currentSeason()
            season = s?.defaultSeason ?? fallback
        }

        careerStats = c?.metrics(dimension: "basic", stage: stage) ?? []
        careerMax = c?.metrics(dimension: "max", stage: stage) ?? []
        careerTable = a?.table(classify: "AVG")
        isCareerLoading = false

        awards = aw?.awards.filter { !$0.details.isEmpty }
            .sorted { $0.details.count > $1.details.count } ?? []
        isAwardsLoading = false

        await loadSeason()
        await loadGameLog()
    }

    private func loadSeason() async {
        isSeasonLoading = true
        defer { isSeasonLoading = false }
        guard !season.isEmpty else { return }
        let root: PlayerSeasonStatsRoot? = try? await client.fetch(
            .playerSeasonStats(playerId: playerId, season: season, stage: stage))
        let groups = root?.dimensionGroups(stage: stage)
        seasonGroups = (groups?.isEmpty == false) ? groups : nil
    }

    private func loadGameLog() async {
        isGameLogLoading = true
        defer { isGameLogLoading = false }
        guard !season.isEmpty else { return }
        let root: PlayerAllMatchStatsRoot? = try? await client.fetch(
            .playerAllMatchStats(playerId: playerId, season: season, stage: stage))
        gameLog = root?.table
    }
}
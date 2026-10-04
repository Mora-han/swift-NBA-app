import SwiftUI
import NBAKit

/// 球员页：默认展示 32 项数据榜，顶部可搜索球员进入个人页
struct PlayersView: View {
    @State private var model = PlayersModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("球员")
                .searchable(text: $model.query, prompt: "搜索球员（中文/英文）")
                .onChange(of: model.query) { _, newValue in
                    Task { await model.search(newValue) }
                }
                .task { await model.start() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.query.isEmpty {
            leaderboard
        } else {
            searchResults
        }
    }

    // MARK: 数据榜

    @ViewBuilder
    private var leaderboard: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 12) {
                    Picker("赛季", selection: $model.season) {
                        ForEach(model.seasonOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    MetricPicker(title: "数据榜", items: model.metricNames,
                                 selection: $model.metricName,
                                 systemImage: "list.number")
                }
                .padding(.horizontal, Theme.gutter)

                if model.isLoading {
                    LoadingBlock()
                } else if let error = model.errorMessage {
                    FailureBlock(message: error) { Task { await model.start(force: true) } }
                } else {
                    RankList(entries: model.rankEntries) { entry in
                        PlayerDetailView(playerId: entry.playerId,
                                         previewName: entry.name,
                                         previewPhoto: entry.photo)
                    }
                    .padding(.horizontal, Theme.gutter)

                    HStack(spacing: 4) {
                        if model.isLoadingFull {
                            ProgressView().controlSize(.mini)
                        }
                        Text(model.isLoadingFull
                             ? "正在加载完整榜单…"
                             : "共 \(model.currentRows.count) 名球员")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, -6)
                }
            }
            .padding(.bottom, 24)
            .readableWidth()
        }
    }

    // MARK: 搜索结果

    @ViewBuilder
    private var searchResults: some View {
        Group {
            if model.isSearching {
                LoadingBlock()
            } else if model.searchResults.isEmpty {
                EmptyBlock(title: "未找到球员", message: model.query)
            } else {
                List(model.searchResults) { player in
                    NavigationLink {
                        PlayerDetailView(playerId: player.playerId ?? "",
                                         previewName: player.displayName,
                                         previewPhoto: player.img)
                    } label: {
                        HStack(spacing: 10) {
                            RemoteImage(urlString: player.img, width: 38, height: 38, cornerRadius: 6)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(player.displayName)
                                    .font(.body)
                                HStack(spacing: 4) {
                                    if let team = player.teamName { Text(team) }
                                    if let pos = player.position { Text(positionText(pos)) }
                                    if let number = player.number?.raw, !number.isEmpty { Text("#\(number)") }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            if let english = player.englishName, !english.isEmpty {
                                Spacer()
                                Text(english)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func positionText(_ raw: String) -> String {
        switch raw.uppercased() {
        case "G": return "后卫"
        case "F": return "前锋"
        case "C": return "中锋"
        default: return raw
        }
    }
}

// MARK: - 模型

@MainActor
@Observable
final class PlayersModel {
    private(set) var metricNames: [String] = []
    private(set) var seasonOptions: [String] = []
    private(set) var rankRows: [PlayerRankRow] = []
    private(set) var searchResults: [SearchPlayer] = []
    private(set) var isLoading = true
    private(set) var isSearching = false
    private(set) var errorMessage: String?

    var query = "" { didSet { } }
    var metricName = "" { didSet { loadRankRows() } }
    var season = "" { didSet { Task { await loadRank(season: season) } } }

    private let client = HupuClient.shared
    private var rankTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var rankCache: [String: [String: [PlayerRankRow]]] = [:]
    private var fullRowsCache: [String: [PlayerRankRow]] = [:]
    private var fullTask: Task<Void, Never>?
    private(set) var isLoadingFull = false
    /// 接口返回的指标顺序（基础指标在前，Dictionary 无序，必须单独保留）
    private var metricOrder: [String] = []

    var currentRows: [PlayerRankRow] { rankRows }

    var rankEntries: [RankList<PlayerDetailView>.Entry] {
        rankRows.map { row in
            RankList<PlayerDetailView>.Entry(
                id: "\(row.playerId ?? "")-\(row.rank ?? 0)",
                rank: row.rank ?? 0,
                playerId: row.playerId ?? "",
                name: row.playerName ?? "-",
                subtitle: [row.teamName, row.teamShortName].compactMap { $0 }.first,
                photo: row.photo,
                value: row.value?.raw ?? "-",
                isUserHighlighted: false)
        }
    }

    func start(force: Bool = false) async {
        guard force || metricNames.isEmpty else { return }
        // 先确定赛季，再用该赛季一次性拉回 32 项榜单（避免拿错赛季拿到空榜）
        let current = await SeasonProvider.shared.currentSeason()
        seasonOptions = [current, SeasonUtility.offset(current, by: -1), SeasonUtility.offset(current, by: -2)]
            .compactMap { $0 }
        if season.isEmpty { season = current }
        await fetchRankPayload(season: current)
        isLoading = false
    }

    private func fetchRankPayload(season targetSeason: String) async {
        rankTask?.cancel()
        rankTask = Task {
            let root: PlayerSeasonRankRoot? = try? await client.fetch(
                .playerSeasonRank(season: targetSeason), ttl: HupuConfig.TTL.rank)
            guard !Task.isCancelled, let root else { return }
            var map: [String: [PlayerRankRow]] = [:]
            var ordered: [String] = []
            for metric in root.metrics {
                if let name = metric.chineseName, !name.isEmpty, map[name] == nil {
                    map[name] = metric.rows
                    ordered.append(name)
                }
            }
            metricOrder = ordered
            rankCache[targetSeason] = map
            guard targetSeason == season else { return }
            metricNames = ordered.filter { !(map[$0]?.isEmpty ?? true) }
            if metricName.isEmpty || map[metricName] == nil {
                metricName = metricNames.first(where: { $0 == "得分" })
                    ?? metricNames.first
                    ?? ""
            }
            loadRankRows()
            errorMessage = nil
        }
        await rankTask?.value
    }

    /// 切换赛季时按需取回该赛季的 32 项榜单
    private func loadRank(season targetSeason: String) async {
        if rankCache[targetSeason] == nil {
            await fetchRankPayload(season: targetSeason)
            return
        }
        metricNames = metricOrder.filter { !(rankCache[targetSeason]?[$0]?.isEmpty ?? true) }
        if metricName.isEmpty || rankCache[targetSeason]?[metricName] == nil {
            metricName = metricNames.first ?? ""
        }
        loadRankRows()
    }

    private func loadRankRows() {
        rankRows = rankCache[season]?[metricName] ?? []
        Task { await fetchFullRowsIfNeeded() }
    }

    /// playerSeasonRank 每项只给前 5 名；选中某项时再用单指标榜单接口取完整 30 强（每页 20，翻 2 页）
    private func fetchFullRowsIfNeeded() async {
        guard let rankType = Self.rankType(for: metricName) else { return }
        let key = "\(season)|\(metricName)"
        guard fullRowsCache[key] == nil, rankRows.count < 30 else { return }

        fullTask?.cancel()
        fullTask = Task {
            var rows: [PlayerRankRow] = []
            for page in 1...2 {
                let result: RankMetric? = try? await client.fetch(
                    .playerSingleDimensionRank(rankType: rankType, season: season, page: page),
                    ttl: HupuConfig.TTL.rank)
                rows.append(contentsOf: result?.rows ?? [])
                if (result?.rows.count ?? 0) < 20 { break }
            }
            guard !Task.isCancelled else { return }
            fullRowsCache[key] = rows
            guard metricName == Self.metricNameFor(rankType: rankType), season == self.season else { return }
            rankRows = rows
            isLoadingFull = false
        }
        isLoadingFull = true
        await fullTask?.value
    }

    /// 指标中文名 ↔ rankType（playerSeasonRank 的 engName 形如 basic.ptsAvg）
    static func rankType(for metricName: String) -> String? {
        switch metricName {
        case "得分": return "basic.ptsAvg"
        case "篮板": return "basic.rebAvg"
        case "助攻": return "basic.astAvg"
        case "抢断": return "basic.stlAvg"
        case "盖帽": return "basic.blkAvg"
        case "前场篮板": return "basic.orebAvg"
        case "后场篮板": return "basic.drebAvg"
        case "失误": return "basic.toAvg"
        case "上场时间": return "basic.minAvg"
        case "投篮命中率": return "basic.fgp"
        case "三分命中率": return "basic.tpp"
        case "罚球命中率": return "basic.ftp"
        case "两双": return "basic.dd"
        case "三双": return "basic.td"
        case "两分命中率": return "basic.twoPointsFgp"
        default: return nil
        }
    }

    static func metricNameFor(rankType: String) -> String? {
        switch rankType {
        case "basic.ptsAvg": return "得分"
        case "basic.rebAvg": return "篮板"
        case "basic.astAvg": return "助攻"
        case "basic.stlAvg": return "抢断"
        case "basic.blkAvg": return "盖帽"
        case "basic.orebAvg": return "前场篮板"
        case "basic.drebAvg": return "后场篮板"
        case "basic.toAvg": return "失误"
        case "basic.minAvg": return "上场时间"
        case "basic.fgp": return "投篮命中率"
        case "basic.tpp": return "三分命中率"
        case "basic.ftp": return "罚球命中率"
        default: return nil
        }
    }

    func search(_ text: String) async {
        let keyword = text.trimmingCharacters(in: .whitespaces)
        searchTask?.cancel()
        guard keyword.count >= 1 else {
            searchResults = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(280))   // 防抖
            guard !Task.isCancelled else { return }
            isSearching = true
            let groups: [SearchGroup]? = try? await client.fetch(.searchPlayer(name: keyword))
            guard !Task.isCancelled else { return }
            searchResults = groups?.flatMap(\.players).prefix(50).map { $0 } ?? []
            isSearching = false
        }
        await searchTask?.value
    }

}
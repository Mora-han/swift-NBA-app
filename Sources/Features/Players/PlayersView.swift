import SwiftUI
import NBAKit

/// 球员页：默认展示 32 项数据榜，顶部可搜索球员进入个人页
struct PlayersView: View {
    @State private var model = PlayersModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("球员")
                .inlineNavigationTitle()
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

                    IdMetricPicker(title: "数据榜",
                                   items: model.pickerItems,
                                   selectionID: $model.metricID,
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
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, -6)
                }
            }
            .padding(.bottom, 24)
            .pageWidth(1200)
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
                            RemoteImage(urlString: player.img, width: 56, height: 56,
                                        cornerRadius: 10, contentMode: .fill)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(player.displayName)
                                    .font(.system(size: 17, weight: .medium))
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
    /// 一项数据榜。key 用「维度.指标」而不是中文名 —— 不同维度存在同名指标
    /// （例如 basic.ptsAvg 和 criticalMoment.ptsAvg 都叫「得分」），
    /// 只按中文名做 key 会互相覆盖，导致某些标签只拿到 5 条数据。
    struct Metric: Identifiable, Hashable {
        let rankType: String     // basic.ptsAvg —— 也是单指标榜单接口的 rankType
        let groupName: String    // 基础 / 进阶 / 关键时刻
        let name: String         // 得分
        var id: String { rankType }

        /// 同名指标加上维度前缀，避免选择器里出现两个「得分」
        var displayName: String { name }
    }

    private(set) var metrics: [Metric] = []
    private(set) var seasonOptions: [String] = []
    private(set) var rankRows: [PlayerRankRow] = []
    private(set) var searchResults: [SearchPlayer] = []
    private(set) var isLoading = true
    private(set) var isSearching = false
    private(set) var errorMessage: String?

    var query = ""
    var metricID = "" { didSet { loadRankRows() } }
    var season = "" { didSet { Task { await loadRank(season: season) } } }

    /// 同名指标加维度前缀，选择器里不会出现两个「得分」
    var pickerItems: [IdentifiedMetric] {
        var seen: [String: Int] = [:]
        return metrics.map { metric in
            let count = (seen[metric.displayName] ?? 0)
            seen[metric.displayName] = count + 1
            let name = count == 0 ? metric.displayName
                                  : "\(metric.displayName)（\(metric.groupName)）"
            return IdentifiedMetric(id: metric.id, displayName: name)
        }
    }

    private let client = HupuClient.shared
    private var rankTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    /// season -> rankType -> 前 5 名
    private var topCache: [String: [String: [PlayerRankRow]]] = [:]
    /// "season|rankType" -> 完整榜单
    private var fullCache: [String: [PlayerRankRow]] = [:]
    private var fullTask: Task<Void, Never>?
    private(set) var isLoadingFull = false

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

    private var currentMetric: Metric? { metrics.first { $0.id == metricID } }

    func start(force: Bool = false) async {
        guard force || metrics.isEmpty else { return }
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

            // 按维度顺序展开，每个指标用 engName 做唯一 key
            var list: [Metric] = []
            var top: [String: [PlayerRankRow]] = [:]
            for group in root.dimensionList ?? [] {
                for item in group.items {
                    guard let rankType = item.engName, !rankType.isEmpty else { continue }
                    top[rankType] = item.rows
                    list.append(Metric(rankType: rankType,
                                       groupName: group.chineseName ?? "",
                                       name: item.chineseName ?? rankType))
                }
            }
            topCache[targetSeason] = top
            guard targetSeason == season else { return }

            metrics = list
            if !metrics.contains(where: { $0.id == metricID }) {
                metricID = metrics.first(where: { $0.rankType == "basic.ptsAvg" })?.id
                    ?? metrics.first?.id
                    ?? ""
            }
            loadRankRows()
            errorMessage = nil
        }
        await rankTask?.value
    }

    private func loadRank(season targetSeason: String) async {
        if topCache[targetSeason] == nil {
            await fetchRankPayload(season: targetSeason)
            return
        }
        if !metrics.contains(where: { $0.id == metricID }) {
            metricID = metrics.first?.id ?? ""
        }
        loadRankRows()
    }

    private func loadRankRows() {
        guard let metric = currentMetric else { rankRows = []; return }
        rankRows = topCache[season]?[metric.rankType] ?? []
        Task { await fetchFullRowsIfNeeded() }
    }

    /// playerSeasonRank 每项只给前 5 名；选中某项时改用单指标榜单接口翻页取完整榜单。
    /// 接口不返回总条数，只能一直翻到某页不足 20 条为止。
    private func fetchFullRowsIfNeeded() async {
        guard let metric = currentMetric else { return }
        let key = "\(season)|\(metric.rankType)"
        guard fullCache[key] == nil, rankRows.count < 30 else { return }

        fullTask?.cancel()
        fullTask = Task {
            var rows: [PlayerRankRow] = []
            var page = 1
            // 上限 60 页（1200 人）防御异常分页，正常 2-3 页就到头了
            while page <= 60 {
                let result: RankMetric? = try? await client.fetch(
                    .playerSingleDimensionRank(rankType: metric.rankType, season: season, page: page),
                    ttl: HupuConfig.TTL.rank)
                let batch = result?.rows ?? []
                rows.append(contentsOf: batch)
                if batch.count < 20 { break }
                page += 1
            }
            guard !Task.isCancelled else { return }
            fullCache[key] = rows
            // 只在用户仍停留在这项指标时才覆盖，避免快速切换时写入错乱的榜单
            guard metric.id == metricID, season == self.season else { return }
            rankRows = rows
            isLoadingFull = false
        }
        isLoadingFull = true
        await fullTask?.value
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

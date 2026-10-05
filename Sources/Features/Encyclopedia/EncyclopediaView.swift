import SwiftUI
import NBAKit

/// 百科：历史选秀（1970-2026）与历届重要荣誉分栏展示。
///
/// 注意：`allPlayerAwardList` 接口**忽略** season 参数，无论传哪个赛季都返回
/// 最近 5 个赛季的数据。因此荣誉必须拉一次全量后按 `winner.season` 本地过滤，
/// 否则切换赛季时界面看起来毫无变化。
struct EncyclopediaView: View {
    @State private var model = EncyclopediaModel()
    @State private var tab: Tab = .draft

    enum Tab: String, CaseIterable, Hashable {
        case draft = "选秀"
        case awards = "荣誉"
        case history = "历史"
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("百科")
                .inlineNavigationTitle()
                .task { await model.start() }
                .refreshable { await model.reload() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.draft == nil && model.awardCategories.isEmpty {
            LoadingBlock()
        } else if let error = model.errorMessage, model.draft == nil, model.awardCategories.isEmpty {
            FailureBlock(message: error) { Task { await model.start() } }
        } else {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 10)

                switch tab {
                case .draft: draftTab
                case .awards: awardsTab
                case .history: historyTab
                }
            }
        }
    }

    // MARK: 历史选秀

    private var draftTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                yearPicker

                if model.isDraftLoading {
                    LoadingBlock()
                } else if let draft = model.draft {
                    if draft.rounds.isEmpty {
                        EmptyBlock(title: "暂无数据", message: "\(model.selectedYear) 年没有选秀记录")
                    } else {
                        ForEach(draft.rounds, id: \.round) { round in
                            draftRound(round)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
            .pageWidth(1200)
        }
        .frame(maxWidth: .infinity)
    }

    private var yearPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "历史选秀",
                          subtitle: "可选 \(model.years.count) 个年份 · \(model.selectedYear) 年共 \(model.totalDraftPicks) 人")
            Picker("年份", selection: $model.selectedYear) {
                ForEach(model.years, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func draftRound(_ round: (round: String, picks: [DraftPick])) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("第 \(round.round) 轮")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Text("\(round.picks.count) 人")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            LazyVStack(spacing: 0) {
                ForEach(Array(round.picks.enumerated()), id: \.element.id) { index, pick in
                    NavigationLink {
                        PlayerDetailView(playerId: pick.playerId ?? "",
                                         previewName: pick.playerName,
                                         previewPhoto: pick.photo)
                    } label: {
                        DraftPickRow(pick: pick)
                    }
                    .buttonStyle(.plain)

                    if index < round.picks.count - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            .cardSurface()
        }
    }

    // MARK: 历届重要荣誉

    private var awardsTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                seasonPicker

                if model.isAwardsLoading {
                    LoadingBlock()
                } else if model.awardCategories.isEmpty {
                    EmptyBlock(title: "暂无荣誉数据", message: "\(model.awardSeason) 赛季还没有公布奖项")
                } else {
                    ForEach(model.awardCategories) { category in
                        awardCategory(category)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
            .pageWidth(1200)
        }
        .frame(maxWidth: .infinity)
    }

    private var seasonPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "历届重要荣誉",
                          subtitle: "\(model.awardSeason) 赛季共 \(model.awardCategories.count) 个奖项")
            Picker("赛季", selection: $model.awardSeason) {
                ForEach(model.awardSeasons, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func awardCategory(_ category: AwardCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                Text(category.awardDesc ?? "")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Text("\(category.winners.count) 位得主")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // MVP / FMVP 等单人奖项每个赛季只有一位得主，直接竖排；
            // 最佳阵容/总冠军等多人奖项同样竖排，卡片自适应列数
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: 10)],
                spacing: 10
            ) {
                ForEach(category.winners) { winner in
                    NavigationLink {
                        PlayerDetailView(playerId: winner.playerId ?? "",
                                         previewName: winner.playerName,
                                         previewPhoto: winner.photo)
                    } label: {
                        winnerCard(winner)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .cardSurface()
    }

    // MARK: 历史总数据榜

    private var historyTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                historyHeader

                if model.isHistoryLoading {
                    LoadingBlock()
                } else if model.historyRows.isEmpty && !model.isHistoryMetricLoading {
                    EmptyBlock(title: "暂无历史数据",
                               message: "虎扑生涯总榜暂无该项指标")
                } else {
                    historyBoard
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
            .pageWidth(1200)
        }
        .frame(maxWidth: .infinity)
    }

    private var historyHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "历史总数据榜",
                          subtitle: "NBA 生涯累计 · 共 \(model.historyMetricNames.count) 项指标 · 非赛季榜")

            Picker("指标", selection: $model.historyMetricName) {
                ForEach(model.historyMetricNames, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var historyBoard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("生涯\(model.historyMetricName)")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                if model.isHistoryMetricLoading {
                    ProgressView().controlSize(.small)
                } else if !model.historyMetricNote.isEmpty {
                    Text(model.historyMetricNote)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            LazyVStack(spacing: 0) {
                ForEach(Array(model.historyRows.enumerated()), id: \.element.id) { index, row in
                    NavigationLink {
                        PlayerDetailView(playerId: row.playerId ?? "",
                                         previewName: row.playerName,
                                         previewPhoto: row.photo)
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(row.rank ?? index + 1)")
                                .font(.statNumber(16, weight: .semibold))
                                .foregroundStyle(index < 3 ? .orange : .secondary)
                                .frame(width: 30, alignment: .trailing)

                            RemoteImage(urlString: row.photo, width: 52, height: 52,
                                        cornerRadius: 26, contentMode: .fill)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.playerName ?? "-")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    // 生涯总榜没有球队字段，右侧展示生涯场均三项
                                    if let pts = row.pts?.raw, !pts.isEmpty { Text("\(pts) 分") }
                                    if let reb = row.reb?.raw, !reb.isEmpty { Text("\(reb) 板") }
                                    if let ast = row.ast?.raw, !ast.isEmpty { Text("\(ast) 助") }
                                }
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Text(row.value?.raw ?? "-")
                                .font(.statNumber(20, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    if index < model.historyRows.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .cardSurface()
        }
    }

    private func winnerCard(_ winner: AwardWinner) -> some View {
        HStack(spacing: 12) {
            RemoteImage(urlString: winner.photo, width: 60, height: 60,
                        cornerRadius: 30, contentMode: .fill)

            VStack(alignment: .leading, spacing: 3) {
                Text(winner.playerName ?? "")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let team = winner.teamName, !team.isEmpty {
                    Text(team)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: Theme.tileRadius))
    }
}

// MARK: - 选秀行

private struct DraftPickRow: View {
    let pick: DraftPick

    var body: some View {
        HStack(spacing: 12) {
            Text("\(pick.rank ?? 0)")
                .font(.statNumber(16, weight: .semibold))
                .foregroundStyle(rankColor)
                .frame(width: 30, alignment: .trailing)

            RemoteImage(urlString: pick.photo, width: 48, height: 48,
                        cornerRadius: 8, contentMode: .fill)

            VStack(alignment: .leading, spacing: 2) {
                Text(pick.playerName ?? "")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let team = pick.draftTeamName { Text(team) }
                    if let pos = pick.position { Text(pos) }
                    if let h = pick.height { Text("\(h)cm") }
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let career = pick.nbaCareer, career.careerPts?.raw.isEmpty == false {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(career.careerPts?.raw ?? "-")
                        .font(.statNumber(17, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("生涯均分")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(.rect)
    }

    private var rankColor: Color {
        switch pick.rank ?? 99 {
        case 1: return .orange
        case 2: return .gray
        case 3: return .brown
        default: return .secondary
        }
    }
}

// MARK: - 模型

@MainActor
@Observable
final class EncyclopediaModel {
    private(set) var years: [String] = []
    private(set) var draft: DraftRoot?
    private(set) var awardCategories: [AwardCategory] = []
    private(set) var awardSeasons: [String] = []
    private(set) var totalDraftPicks = 0
    private(set) var isLoading = true
    private(set) var isHistoryLoading = true
    private(set) var historyMetricNames: [String] = []
    private(set) var historyRows: [PlayerRankRow] = []
    private(set) var isHistoryMetricLoading = false
    private(set) var historyMetricNote = ""
    /// 中文名 -> rankType
    private var historyRankTypes: [String: String] = [:]
    private var historyTask: Task<Void, Never>?
    private(set) var isDraftLoading = true
    private(set) var isAwardsLoading = true
    private(set) var errorMessage: String?

    var selectedYear = "" {
        didSet {
            if oldValue != selectedYear, !selectedYear.isEmpty { Task { await loadDraft() } }
        }
    }

    /// 选择器用中文名做绑定，切换后换算成 rankType 拉数据。
    /// 只保留这一个写入入口，避免两个属性互相 didSet 造成递归。
    var historyMetricName = "" {
        didSet {
            guard oldValue != historyMetricName, !historyMetricName.isEmpty else { return }
            Task { await loadHistoryMetric() }
        }
    }

    var awardSeason = "" {
        didSet {
            if oldValue != awardSeason, !awardSeason.isEmpty { Task { await applyAwardSeason() } }
        }
    }

    private let client = HupuClient.shared
    private var draftCache: [String: DraftRoot] = [:]
    /// 接口返回的全量荣誉（近 5 个赛季），本地按赛季过滤
    private var allAwards: AllAwardsRoot?

    func start() async {
        if years.isEmpty { await loadYears() }
        await loadAwards()
        await loadHistory()
        isLoading = false
    }

    func reload() async {
        draftCache = [:]
        allAwards = nil
        await start()
    }

    private func loadYears() async {
        let list: [String]? = try? await client.fetch(.draftYears, ttl: HupuConfig.TTL.encyclopedia)
        guard let list, !list.isEmpty else {
            errorMessage = "无法获取选秀年份列表"
            return
        }
        years = list.sorted(by: >)
        let thisYear = String(SeasonUtility.season(for: .now).prefix(4))
        selectedYear = years.contains(thisYear) ? thisYear : (years.first { $0 < thisYear } ?? thisYear)
        errorMessage = nil
        await loadDraft()
    }

    private func loadDraft() async {
        guard !selectedYear.isEmpty else { return }
        if let cached = draftCache[selectedYear] {
            draft = cached
            isDraftLoading = false
            return
        }
        isDraftLoading = true
        defer { isDraftLoading = false }
        let root: DraftRoot? = try? await client.fetch(.draft(year: selectedYear),
                                                      ttl: HupuConfig.TTL.encyclopedia)
        draft = root
        draftCache[selectedYear] = root
        totalDraftPicks = (root?.rounds ?? []).reduce(0) { $0 + $1.picks.count }
    }

    // MARK: 历史总数据榜

    /// 生涯总榜菜单（grain=totals）：一次拿全部 23 项累计指标，每项附前 5 名。
    /// 与「球员」页的赛季榜（playerSeasonRank）是两套数据，这里没有赛季维度。
    private func loadHistory() async {
        isHistoryLoading = true
        defer { isHistoryLoading = false }

        let root: CareerRankRoot? = try? await client.fetch(
            .careerTotalRankMenu, ttl: HupuConfig.TTL.encyclopedia)
        guard let root else { return }

        var byName: [String: String] = [:]     // 中文名 -> rankType
        var names: [String] = []
        for metric in root.metrics {
            guard let rankType = metric.engName, !rankType.isEmpty else { continue }
            let raw = metric.chineseName ?? rankType
            guard byName[raw] == nil else { continue }
            byName[raw] = rankType
            names.append(raw)
        }
        historyRankTypes = byName
        historyMetricNames = names

        // 菜单首位是「出场数」，历史榜按惯例默认落在「总得分」
        if historyRankTypes[historyMetricName] == nil {
            historyMetricName = names.first { byName[$0] == "basic.pts" } ?? names.first ?? ""
        } else {
            await loadHistoryMetric()
        }
    }

    /// 单指标生涯总榜翻页：20 条/页，接口翻到约 1000 名仍有数据，
    /// 本地取 5 页 = 100 名即可（与赛季单指标榜口径一致）。
    private func loadHistoryMetric() async {
        guard let rankType = historyRankTypes[historyMetricName] else { return }
        historyTask?.cancel()
        historyTask = Task {
            var rows: [PlayerRankRow] = []
            var page = 1
            while page <= 5 {
                let result: CareerRankPageRoot? = try? await client.fetch(
                    .careerTotalRank(rankType: rankType, page: page),
                    ttl: HupuConfig.TTL.encyclopedia)
                let batch = result?.rows ?? []
                rows.append(contentsOf: batch)
                if batch.count < 20 { break }
                page += 1
            }
            guard !Task.isCancelled else { return }
            historyRows = rows
            historyMetricNote = rows.count >= 100 ? "共 100 名" : "共 \(rows.count) 名"
            isHistoryMetricLoading = false
        }
        isHistoryMetricLoading = true
        await historyTask?.value
    }

    /// 拉一次全量荣誉；赛季列表直接取自数据里真实存在的赛季，避免给出空赛季
    private func loadAwards() async {
        isAwardsLoading = true
        defer { isAwardsLoading = false }

        let root: AllAwardsRoot? = try? await client.fetch(
            .allPlayerAwardList(season: ""), ttl: HupuConfig.TTL.encyclopedia)
        allAwards = root

        let seasons = Set((root?.categories ?? [])
            .flatMap { $0.winners }
            .compactMap(\.season))
            .sorted(by: >)

        if !seasons.isEmpty {
            awardSeasons = seasons
        } else {
            // 兜底：接口没给到赛季时用日期推断补 8 个赛季
            let current = await SeasonProvider.shared.currentSeason()
            awardSeasons = (0..<8).compactMap { SeasonUtility.offset(current, by: -$0) }
        }

        if awardSeason.isEmpty {
            let current = await SeasonProvider.shared.currentSeason()
            awardSeason = awardSeasons.contains(current) ? current : (awardSeasons.first ?? current)
        }
        applyAwardFilter()
    }

    /// 只做本地过滤，不再发请求（接口对 season 无效）
    private func applyAwardSeason() async {
        applyAwardFilter()
    }

    private func applyAwardFilter() {
        let target = awardSeason
        awardCategories = (allAwards?.categories ?? [])
            .map { category -> AwardCategory in
                let filtered = category.winners.filter { $0.season == target }
                return category.filtering(winners: filtered)
            }
            .filter { !$0.winners.isEmpty }
    }
}

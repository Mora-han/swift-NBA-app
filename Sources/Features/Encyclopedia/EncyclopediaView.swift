import SwiftUI
import NBAKit

/// 百科：历史选秀（1970-2026）+ 历届重要荣誉得主
struct EncyclopediaView: View {
    @State private var model = EncyclopediaModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("百科")
                .task { await model.start() }
                .refreshable { await model.reload() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.draft == nil {
            LoadingBlock()
        } else if let error = model.errorMessage, model.draft == nil {
            FailureBlock(message: error) { Task { await model.start() } }
        } else {
            List {
                // 概览统计
                Section {
                    HStack(spacing: 0) {
                        overviewItem("可选年份", "\(model.years.count)", systemImage: "calendar")
                        Divider().frame(height: 34)
                        overviewItem("本届球员", "\(model.totalDraftPicks)", systemImage: "person.2")
                        Divider().frame(height: 34)
                        overviewItem("荣誉奖项", "\(model.awardCategories.count)", systemImage: "trophy")
                    }
                    .padding(.vertical, 6)
                }

                // 选秀年份选择
                Section("历史选秀") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(model.selectedYear)
                                .font(.title3.weight(.bold))
                                .contentTransition(.numericText())
                            Spacer()
                            Picker("年份", selection: $model.selectedYear) {
                                ForEach(model.years, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                        }

                        if let draft = model.draft {
                            if draft.rounds.isEmpty {
                                Text("该年份暂无数据")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(draft.rounds, id: \.round) { round in
                                    DisclosureGroup {
                                        ForEach(round.picks) { pick in
                                            NavigationLink {
                                                PlayerDetailView(playerId: pick.playerId ?? "",
                                                                 previewName: pick.playerName,
                                                                 previewPhoto: pick.photo)
                                            } label: {
                                                DraftPickRow(pick: pick)
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            Text("第 \(round.round) 轮")
                                                .font(.subheadline.weight(.medium))
                                            Spacer()
                                            Text("\(round.picks.count) 人")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        } else {
                            LoadingBlock()
                        }
                    }
                }

                // 历届荣誉
                Section("历届重要荣誉") {
                    ForEach(model.awardCategories) { category in
                        NavigationLink {
                            AwardCategoryView(category: category)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "trophy.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(category.awardDesc ?? "")
                                        .font(.subheadline.weight(.medium))
                                    Text("\(category.winnerCount) 位得主")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            #if os(iOS)
            .scrollContentBackground(.hidden)
            #endif
        }
    }

    private func overviewItem(_ title: String, _ value: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 选秀行

private struct DraftPickRow: View {
    let pick: DraftPick

    var body: some View {
        HStack(spacing: 10) {
            Text("\(pick.rank ?? 0)")
                .font(.statNumber(13, weight: .semibold))
                .foregroundStyle(rankColor)
                .frame(width: 22, alignment: .trailing)

            RemoteImage(urlString: pick.photo, width: 32, height: 32, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(pick.playerName ?? "")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let team = pick.draftTeamName { Text(team) }
                    if let pos = pick.position { Text(pos) }
                    if let h = pick.height { Text("\(h)cm") }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let career = pick.nbaCareer, career.careerPts?.raw.isEmpty == false {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(career.careerPts?.raw ?? "-")
                        .font(.statNumber(13, weight: .semibold))
                        .monospacedDigit()
                    Text("生涯均分")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 3)
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

// MARK: - 荣誉分类页

struct AwardCategoryView: View {
    let category: AwardCategory

    var body: some View {
        List {
            ForEach(category.winners.sorted(by: { $0.season ?? "" > $1.season ?? "" })) { winner in
                NavigationLink {
                    PlayerDetailView(playerId: winner.playerId ?? "",
                                     previewName: winner.playerName,
                                     previewPhoto: winner.photo)
                } label: {
                    HStack(spacing: 10) {
                        RemoteImage(urlString: winner.photo, width: 40, height: 40, cornerRadius: 6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(winner.playerName ?? "")
                                .font(.subheadline.weight(.medium))
                            HStack(spacing: 5) {
                                Text(winner.season ?? "")
                                if let team = winner.teamName { Text(team) }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let pts = winner.pts, pts > 0 {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(String(format: "%.1f", pts))
                                    .font(.statNumber(14, weight: .semibold))
                                    .monospacedDigit()
                                HStack(spacing: 3) {
                                    if let reb = winner.reb { Text(String(format: "%.1f板", reb)) }
                                    if let ast = winner.asts { Text(String(format: "%.1f助", ast)) }
                                }
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(category.awardDesc ?? "荣誉")
        .inlineNavigationTitle()
    }
}

// MARK: - 模型

@MainActor
@Observable
final class EncyclopediaModel {
    private(set) var years: [String] = []
    private(set) var draft: DraftRoot?
    private(set) var awardCategories: [AwardCategory] = []
    private(set) var totalDraftPicks = 0
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    var selectedYear = "" {
        didSet {
            if oldValue != selectedYear && !selectedYear.isEmpty { Task { await loadDraft() } }
        }
    }

    /// 当年选秀要等夏天才出，默认回退到最近一届有数据的年份
    private func fallbackYear(_ thisYear: String) -> String {
        years.first { $0 < thisYear } ?? thisYear
    }

    private let client = HupuClient.shared
    private var draftCache: [String: DraftRoot] = [:]

    func start() async {
        if years.isEmpty { await loadYears() }
        await loadDraft()
        await loadAwards()
        isLoading = false
    }

    func reload() async {
        draftCache = [:]
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
        selectedYear = years.contains(thisYear) ? thisYear : fallbackYear(thisYear)
        errorMessage = nil
    }

    private func loadDraft() async {
        guard !selectedYear.isEmpty else { return }
        if let cached = draftCache[selectedYear] {
            draft = cached
            return
        }
        let root: DraftRoot? = try? await client.fetch(.draft(year: selectedYear),
                                                      ttl: HupuConfig.TTL.encyclopedia)
        draft = root
        draftCache[selectedYear] = root
        totalDraftPicks = (root?.rounds ?? []).reduce(0) { $0 + $1.picks.count }
    }

    private func loadAwards() async {
        guard awardCategories.isEmpty else { return }
        let season = await SeasonProvider.shared.currentSeason()
        let root: AllAwardsRoot? = try? await client.fetch(
            .allPlayerAwardList(season: season), ttl: HupuConfig.TTL.encyclopedia)
        awardCategories = (root?.categories ?? []).filter { !$0.winners.isEmpty }
    }
}
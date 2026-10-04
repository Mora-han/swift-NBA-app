import SwiftUI
import NBAKit

/// 百科：历史选秀（1970-2026）+ 历届重要荣誉（可切赛季）
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
                overview
                draftSection
                awardsSection
            }
            .listStyle(.inset)
        }
    }

    // MARK: 概览

    private var overview: some View {
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

    // MARK: 历史选秀

    private var draftSection: some View {
        Section("历史选秀") {
            Picker("年份", selection: $model.selectedYear) {
                ForEach(model.years, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)

            if model.isDraftLoading {
                LoadingBlock()
            } else if let draft = model.draft {
                if draft.rounds.isEmpty {
                    Text("\(model.selectedYear) 年暂无数据")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(draft.rounds, id: \.round) { round in
                        draftRound(round)
                    }
                }
            }
        }
    }

    private func draftRound(_ round: (round: String, picks: [DraftPick])) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("第 \(round.round) 轮")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(round.picks.count) 人")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)

            ForEach(round.picks) { pick in
                NavigationLink {
                    PlayerDetailView(playerId: pick.playerId ?? "",
                                     previewName: pick.playerName,
                                     previewPhoto: pick.photo)
                } label: {
                    DraftPickRow(pick: pick)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: 历届重要荣誉

    private var awardsSection: some View {
        Section {
            Picker("赛季", selection: $model.awardSeason) {
                ForEach(model.awardSeasons, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)

            if model.isAwardsLoading {
                LoadingBlock()
            } else if model.awardCategories.isEmpty {
                Text("该赛季暂无荣誉数据")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                // 每个奖项标题下直接列出该奖项的球员与头像
                ForEach(model.awardCategories) { category in
                    awardCategory(category)
                }
            }
        } header: {
            Text("历届重要荣誉")
        } footer: {
            Text("选择赛季查看该赛季各项荣誉得主")
        }
    }

    private func awardCategory(_ category: AwardCategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "trophy.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(category.awardDesc ?? "")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(category.winnerCount) 位得主")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // 横向排列得主，标题下方直接看到球员和头像
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(category.winners.sorted { ($0.season ?? "") > ($1.season ?? "") }) { winner in
                        NavigationLink {
                            PlayerDetailView(playerId: winner.playerId ?? "",
                                             previewName: winner.playerName,
                                             previewPhoto: winner.photo)
                        } label: {
                            winnerChip(winner)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, 6)
    }

    private func winnerChip(_ winner: AwardWinner) -> some View {
        VStack(spacing: 4) {
            RemoteImage(urlString: winner.photo, width: 46, height: 46,
                        cornerRadius: 23, contentMode: .fill)
            Text(winner.playerName ?? "")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 62)
            Text(winner.teamName ?? "")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 62)
        }
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
                .frame(width: 24, alignment: .trailing)

            RemoteImage(urlString: pick.photo, width: 34, height: 34, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(pick.playerName ?? "")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
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
                        .foregroundStyle(.primary)
                    Text("生涯均分")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 5)
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
    private(set) var isDraftLoading = true
    private(set) var isAwardsLoading = true
    private(set) var errorMessage: String?

    var selectedYear = "" {
        didSet {
            if oldValue != selectedYear && !selectedYear.isEmpty { Task { await loadDraft() } }
        }
    }

    var awardSeason = "" {
        didSet {
            if oldValue != awardSeason && !awardSeason.isEmpty { Task { await loadAwards() } }
        }
    }

    private let client = HupuClient.shared
    private var draftCache: [String: DraftRoot] = [:]

    func start() async {
        if years.isEmpty { await loadYears() }
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

    private func loadAwards() async {
        isAwardsLoading = true
        defer { isAwardsLoading = false }
        if awardSeasons.isEmpty {
            let current = await SeasonProvider.shared.currentSeason()
            awardSeasons = (0..<8).compactMap { SeasonUtility.offset(current, by: -$0) }
            if awardSeason.isEmpty { awardSeason = current }
        }
        guard !awardSeason.isEmpty else { return }
        let root: AllAwardsRoot? = try? await client.fetch(
            .allPlayerAwardList(season: awardSeason), ttl: HupuConfig.TTL.encyclopedia)
        awardCategories = (root?.categories ?? []).filter { !$0.winners.isEmpty }
    }
}

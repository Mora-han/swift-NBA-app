import SwiftUI
import NBAKit

/// 球队队徽补全：teams.json 里部分队徽为 null，用 standings 接口返回的 logoLink 补齐。
/// standings 一次就带全部 30 队队徽，缓存后离线可用。
@MainActor
@Observable
final class TeamLogoStore {
    private(set) var logos: [String: String] = [:]
    private(set) var order: [String] = []     // 按当前战绩排名排序的 teamId
    private(set) var standings: [String: TeamStanding] = [:]
    private(set) var loaded = false

    private let client = HupuClient.shared

    func logo(for teamId: String) -> String? {
        logos[teamId] ?? TeamRegistry.team(id: teamId)?.logo
    }

    func standing(for teamId: String) -> TeamStanding? {
        standings[teamId]
    }

    func load() async {
        if loaded { return }
        let season = await SeasonProvider.shared.currentSeason()
        // 用常规赛数据：新赛季未开赛时 standings 默认返回季后赛（名次为 #0），
        // 卡片展示常规赛战绩更有意义
        let root: StandingRoot? = try? await client.fetch(
            .teamStanding(stage: "REGULAR", season: season),
            ttl: HupuConfig.TTL.standings)
        guard let root else { return }
        var map: [String: String] = [:]
        var seq: [String] = []
        var records: [String: TeamStanding] = [:]
        for row in (root.east + root.west) {
            guard let id = row.teamId else { continue }
            if let logo = row.logoLink, !logo.isEmpty { map[id] = logo }
            seq.append(id)
            records[id] = row
        }
        logos = map
        order = seq
        standings = records
        loaded = true
    }
}
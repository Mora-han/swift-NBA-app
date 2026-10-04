import SwiftUI
import NBAKit

/// 球队队徽补全：teams.json 里部分队徽为 null，用 standings 接口返回的 logoLink 补齐。
/// standings 一次就带全部 30 队队徽，缓存后离线可用。
@MainActor
@Observable
final class TeamLogoStore {
    private(set) var logos: [String: String] = [:]
    private(set) var order: [String] = []     // 按当前战绩排名排序的 teamId
    private(set) var loaded = false

    private let client = HupuClient.shared

    func logo(for teamId: String) -> String? {
        logos[teamId] ?? TeamRegistry.team(id: teamId)?.logo
    }

    func load() async {
        if loaded { return }
        let root: StandingRoot? = try? await client.fetch(.teamStandingList,
                                                         ttl: HupuConfig.TTL.standings)
        guard let root else { return }
        var map: [String: String] = [:]
        var seq: [String] = []
        for row in (root.east + root.west) {
            guard let id = row.teamId else { continue }
            if let logo = row.logoLink, !logo.isEmpty { map[id] = logo }
            seq.append(id)
        }
        logos = map
        order = seq
        loaded = true
    }
}
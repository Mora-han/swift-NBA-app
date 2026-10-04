import Foundation

// MARK: - 30 队静态注册表（teams.json 随包分发，离线可用）

public struct LeagueTeam: Decodable, Sendable, Hashable, Identifiable {
    public let teamId: String
    public let abbr: String?
    public let name: String
    public let logo: String?

    public var id: String { teamId }
}

public enum TeamRegistry {
    public static let all: [LeagueTeam] = {
        guard let url = Bundle.module.url(forResource: "teams", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let teams = try? JSONDecoder().decode([LeagueTeam].self, from: data)
        else { return [] }
        return teams
    }()

    public static func team(id: String) -> LeagueTeam? {
        all.first { $0.teamId == id }
    }
}

// MARK: - 赛季推断

public enum SeasonUtility {
    /// 按日期推断 NBA 赛季（10 月起为 y-(y+1)，1-9 月为 (y-1)-y）
    public static func season(for date: Date = .now) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        return m >= 10 ? "\(y)-\(y + 1)" : "\(y - 1)-\(y)"
    }

    /// "2025-2026" → "2024-2025"（by = -1）
    public static func offset(_ season: String, by years: Int) -> String? {
        let parts = season.split(separator: "-")
        guard parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]) else { return nil }
        return "\(start + years)-\(end + years)"
    }
}

/// 当前赛季来源：优先取战绩接口返回的官方赛季（覆盖休赛期/新旧赛季交替），
/// 拿不到就按日期推断；结果缓存 1 小时。
public actor SeasonProvider {
    public static let shared = SeasonProvider()

    private var cached: (season: String, at: Date)?

    public init() {}

    /// 返回「当前正在进行的赛季」：
    /// 虎扑 standings 会把未开赛的新赛季也带出来（新赛季所有球队 0-0），
    /// 因此只有当返回的赛季里已有球队赢过球时才采信，否则回退到按日期推断的赛季。
    public func currentSeason() async -> String {
        if let c = cached, Date.now.timeIntervalSince(c.at) < 3600 { return c.season }
        let fetched: StandingRoot? = try? await HupuClient.shared.fetch(
            HupuEndpoint.teamStandingList, ttl: 3600)
        if let season = fetched?.season, season.count == 9 {
            let played = (fetched?.east ?? [] + (fetched?.west ?? []))
                .contains { ($0.won ?? 0) + ($0.lost ?? 0) > 0 }
            if played {
                cached = (season, .now)
                return season
            }
        }
        return SeasonUtility.season()
    }
}

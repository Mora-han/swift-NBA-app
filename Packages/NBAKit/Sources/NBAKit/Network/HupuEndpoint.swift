import Foundation

/// 虎扑 NBA 接口全局配置（见 API-Collect/hupu-api/README.md）
public enum HupuConfig {
    /// 主力网关（国内阿里云，实测 TTFB 中位 80ms）
    public static let baseURL = URL(string: "https://games.mobileapi.hupu.com")!
    /// 版本路径仅作路由用，实测 1/7.5.25 ~ 1/8.2.10 各版本返回一致，可随时降级替换
    public static let versionPath = "3/7.5.60"
    /// 必须带正常 iPhone UA，裸 UA 可能被拦
    public static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1"
    /// 进行中比赛轮询间隔（接口文档建议 ≥10s）
    public static let livePollInterval: TimeInterval = 12
    /// 比分页整表刷新间隔
    public static let scoresRefreshInterval: TimeInterval = 30

    /// 静态数据缓存时长
    public enum TTL {
        public static let schedule: TimeInterval = 20
        public static let live: TimeInterval = 8
        public static let standings: TimeInterval = 60
        public static let rank: TimeInterval = 300
        public static let roster: TimeInterval = 600
        public static let encyclopedia: TimeInterval = 6 * 3600
    }
}

// MARK: - 统一响应信封

public struct HupuEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    public let errorCode: String?
    public let errorMsg: String?
    public let result: T?
    public let success: Bool?
    public let status: Int?
}

/// 仅识别外壳、不解析 result 内容，用于判断「是否为信封结构」以及把业务错误单独抛出
struct ResponseShell: Decodable {
    let errorMsg: String?
    let success: Bool?
    let result: IgnoredValue?
    let status: Int?
}

/// 任意 JSON 值的占位（只要求「存在」，不要求内容）
struct IgnoredValue: Decodable {
    init(from decoder: Decoder) throws {}
}

/// salary 接口信封（/salary/v1/*）
struct SalaryEnvelope<T: Decodable & Sendable>: Decodable {
    let status: Int?
    let msg: String?
    let result: T?
}

public enum HupuError: Error, LocalizedError {
    case http(Int)
    case business(String) // success=false，errorMsg 为中文，如「比赛不存在」
    case emptyResult
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .http(let c): return "网络错误（HTTP \(c)）"
        case .business(let m): return m
        case .emptyResult: return "接口返回空数据"
        case .decoding(let m): return "解析失败: \(m)"
        }
    }
}

// MARK: - 接口定义

public enum HupuEndpoint: Sendable, Hashable {
    // 比赛
    case scheduleList(day: String?)                 // 赛程窗口（day=yyyyMMdd 锚点）
    case matchInfo(matchId: String)                 // 比分/状态/节次/转播
    case live(matchId: String)                      // 实时比分 + 文字直播
    case boxscore(matchId: String, teamId: String)  // 单队球员技术统计
    case teamMatchStats(matchId: String)            // 两队整体数据对比

    // 球队
    case teamStandingList                           // 东西部战绩（默认当前阶段）
    case teamStanding(stage: String)                // 指定阶段战绩（REGULAR/PLAYOFF）
    case teamSeasonStatsRank(rankType: String, season: String) // 单指标球队榜（30 队）
    case teamSeasonStatsAllRank                     // 全指标球队榜清单（指标菜单）
    case teamBasicInfo(teamId: String)
    case teamPlayerList(teamId: String)
    case teamSeasonStats(teamId: String, season: String)
    case teamAwardList(teamId: String)
    case teamShirtRetired(teamId: String)
    case teamHistoryPlayerStatsRank(teamId: String)
    case teamScheduleList(teamId: String)

    // 球员
    case searchPlayer(name: String)
    case playerInfo(playerId: String)
    case playerLeagueSeason(playerId: String)
    case playerSeasonStats(playerId: String, season: String, stage: String)
    case playerCareerStats(playerId: String)
    case playerAllSeasonStats(playerId: String)
    case playerAllMatchStats(playerId: String, season: String, stage: String)
    case playerAwardList(playerId: String)
    case playerSeasonRank(season: String)
    case playerSingleDimensionRank(rankType: String, season: String, page: Int)

    // 百科
    case draftYears
    case draft(year: String)
    case allPlayerAwardList(season: String)

    var path: String {
        let v = "/\(HupuConfig.versionPath)/basketballapi"
        switch self {
        case .scheduleList: return "\(v)/scheduleList"
        case .matchInfo: return "\(v)/matchInfo"
        case .live: return "\(v)/live"
        case .boxscore: return "\(v)/teamMatchRosterScoreStats"
        case .teamMatchStats: return "\(v)/teamMatchStats"
        case .teamStandingList: return "\(v)/teamStandingList"
        case .teamStanding: return "\(v)/teamStandingList"
        case .teamSeasonStatsRank: return "\(v)/teamSeasonStatsRank"
        case .teamSeasonStatsAllRank: return "\(v)/teamSeasonStatsAllRank"
        case .teamBasicInfo: return "\(v)/teamBasicInfo"
        case .teamPlayerList: return "\(v)/teamPlayerList"
        case .teamSeasonStats: return "\(v)/teamSeasonStats"
        case .teamAwardList: return "\(v)/teamAwardList"
        case .teamShirtRetired: return "\(v)/teamShirtRetired"
        case .teamHistoryPlayerStatsRank: return "\(v)/team/history/playerStatsRank"
        case .teamScheduleList: return "\(v)/teamScheduleList"
        case .searchPlayer: return "\(v)/searchPlayer"
        case .playerInfo: return "\(v)/playerInfo"
        case .playerLeagueSeason: return "\(v)/player/leagueSeason"
        case .playerSeasonStats: return "\(v)/playerSeasonStats"
        case .playerCareerStats: return "\(v)/playerCareerStats"
        case .playerAllSeasonStats: return "\(v)/playerAllSeasonStats"
        case .playerAllMatchStats: return "\(v)/playerAllMatchStats"
        case .playerAwardList: return "\(v)/playerAwardList"
        case .playerSeasonRank: return "\(v)/playerSeasonRank"
        case .playerSingleDimensionRank: return "\(v)/playerSingleDimensionSeasonRank"
        case .draftYears: return "\(v)/draftYearConfig"
        case .draft: return "\(v)/players/draft"
        case .allPlayerAwardList: return "\(v)/allPlayerAwardList"
        }
    }

    var query: [URLQueryItem] {
        switch self {
        case .scheduleList(let day):
            var q = [URLQueryItem(name: "competitionTag", value: "nba")]
            if let day { q.append(URLQueryItem(name: "day", value: day)) }
            return q
        case .matchInfo(let m), .live(let m):
            return [URLQueryItem(name: "matchId", value: m)]
        case .boxscore(let m, let t):
            return [URLQueryItem(name: "matchId", value: m),
                    URLQueryItem(name: "teamId", value: t),
                    URLQueryItem(name: "userId", value: "")]
        case .teamMatchStats(let m):
            return [URLQueryItem(name: "matchId", value: m)]
        case .teamStandingList:
            return nbaOffline
        case .teamStanding(let stage):
            return nbaOffline + [URLQueryItem(name: "competitionStageType", value: stage)]
        case .teamSeasonStatsRank(let rankType, let season):
            return [URLQueryItem(name: "rankType", value: rankType),
                    URLQueryItem(name: "leagueType", value: "NBA"),
                    URLQueryItem(name: "matchType", value: "REGULAR"),
                    URLQueryItem(name: "season", value: season),
                    URLQueryItem(name: "competitionLeagueType", value: "NBA"),
                    URLQueryItem(name: "competitionType", value: "NBA"),
                    URLQueryItem(name: "competitionStageType", value: "REGULAR")]
        case .teamSeasonStatsAllRank:
            return [URLQueryItem(name: "competitionType", value: "NBA"),
                    URLQueryItem(name: "competitionLeagueType", value: "NBA"),
                    URLQueryItem(name: "offline", value: "offline")]
        case .teamBasicInfo(let t):
            return [URLQueryItem(name: "teamId", value: t),
                    URLQueryItem(name: "leagueType", value: "NBA")]
        case .teamPlayerList(let t):
            return [URLQueryItem(name: "teamId", value: t),
                    URLQueryItem(name: "leagueType", value: "NBA")]
        case .teamSeasonStats(let t, let season):
            return [URLQueryItem(name: "teamId", value: t),
                    URLQueryItem(name: "season", value: season),
                    URLQueryItem(name: "leagueType", value: "NBA"),
                    URLQueryItem(name: "competitionLeagueType", value: "NBA"),
                    URLQueryItem(name: "competitionType", value: "NBA")]
        case .teamAwardList(let t):
            return [URLQueryItem(name: "teamId", value: t)]
        case .teamShirtRetired(let t):
            return [URLQueryItem(name: "teamId", value: t)]
        case .teamHistoryPlayerStatsRank(let t):
            return [URLQueryItem(name: "teamId", value: t)]
        case .teamScheduleList(let t):
            return [URLQueryItem(name: "teamId", value: t),
                    URLQueryItem(name: "competitionType", value: "NBA"),
                    URLQueryItem(name: "competitionLeagueType", value: "NBA")]
        case .searchPlayer(let name):
            return [URLQueryItem(name: "playerName", value: name),
                    URLQueryItem(name: "leagueType", value: "NBA")]
        case .playerInfo(let p):
            return [URLQueryItem(name: "playerId", value: p)]
        case .playerLeagueSeason(let p):
            return [URLQueryItem(name: "playerId", value: p),
                    URLQueryItem(name: "leagueType", value: "NBA")]
        case .playerSeasonStats(let p, let season, let stage):
            return [URLQueryItem(name: "playerId", value: p),
                    URLQueryItem(name: "season", value: season),
                    URLQueryItem(name: "leagueType", value: "NBA"),
                    URLQueryItem(name: "competitionLeagueType", value: "NBA"),
                    URLQueryItem(name: "competitionType", value: "NBA"),
                    URLQueryItem(name: "competitionStageType", value: stage)]
        case .playerCareerStats(let p), .playerAllSeasonStats(let p):
            return [URLQueryItem(name: "playerId", value: p),
                    URLQueryItem(name: "competitionType", value: "NBA"),
                    URLQueryItem(name: "competitionLeagueType", value: "NBA")]
        case .playerAllMatchStats(let p, let season, let stage):
            return [URLQueryItem(name: "playerId", value: p),
                    URLQueryItem(name: "leagueType", value: "NBA"),
                    URLQueryItem(name: "season", value: season),
                    URLQueryItem(name: "competitionStageType", value: stage)]
        case .playerAwardList(let p):
            return [URLQueryItem(name: "playerId", value: p),
                    URLQueryItem(name: "competitionType", value: "NBA"),
                    URLQueryItem(name: "competitionLeagueType", value: "NBA")]
        case .playerSeasonRank(let season):
            return [URLQueryItem(name: "competitionType", value: "NBA"),
                    URLQueryItem(name: "competitionLeagueType", value: "NBA"),
                    URLQueryItem(name: "offline", value: "offline"),
                    URLQueryItem(name: "season", value: season),
                    URLQueryItem(name: "competitionStageType", value: "REGULAR")]
        case .playerSingleDimensionRank(let rankType, let season, let page):
            // playerType 必须是 normal（all/ALL/1/2 全部服务端报错），pageNo 每页 20 条
            return [URLQueryItem(name: "competitionType", value: "NBA"),
                    URLQueryItem(name: "competitionLeagueType", value: "NBA"),
                    URLQueryItem(name: "leagueType", value: "NBA"),
                    URLQueryItem(name: "rankType", value: rankType),
                    URLQueryItem(name: "season", value: season),
                    URLQueryItem(name: "competitionStageType", value: "REGULAR"),
                    URLQueryItem(name: "playerType", value: "normal"),
                    URLQueryItem(name: "pageNo", value: String(page))]
            // playerType 必须是 normal（all/ALL/1/2 全部服务端报错），pageNo 每页 20 条
            return [URLQueryItem(name: "competitionType", value: "NBA"),
                    URLQueryItem(name: "competitionLeagueType", value: "NBA"),
                    URLQueryItem(name: "leagueType", value: "NBA"),
                    URLQueryItem(name: "rankType", value: rankType),
                    URLQueryItem(name: "season", value: season),
                    URLQueryItem(name: "competitionStageType", value: "REGULAR"),
                    URLQueryItem(name: "playerType", value: "normal"),
                    URLQueryItem(name: "pageNo", value: String(page))]
        case .draftYears:
            return [URLQueryItem(name: "leagueType", value: "NBA"),
                    URLQueryItem(name: "competitionType", value: "NBA")]
        case .draft(let year):
            return [URLQueryItem(name: "draftYear", value: year),
                    URLQueryItem(name: "leagueType", value: "NBA")]
        case .allPlayerAwardList(let season):
            return [URLQueryItem(name: "leagueType", value: "NBA"),
                    URLQueryItem(name: "competitionType", value: "NBA"),
                    URLQueryItem(name: "season", value: season)]
        }
    }

    private var nbaOffline: [URLQueryItem] {
        [URLQueryItem(name: "competitionType", value: "NBA"),
         URLQueryItem(name: "competitionLeagueType", value: "NBA"),
         URLQueryItem(name: "offline", value: "offline")]
    }

    /// 缓存键（同路径同参数共用）
    var cacheKey: String {
        let q = query.map { "\($0.name)=\(qvalue($0.value))" }.joined(separator: "&")
        return path + "?" + q
    }

    private func qvalue(_ v: String?) -> String { v ?? "" }
}

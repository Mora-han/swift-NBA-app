import Foundation

/// 可同时接受 JSON 字符串 / 数字的展示型字段（虎扑同一字段历史上出现过两种类型）
public struct FlexString: Decodable, Hashable, Sendable {
    public let raw: String

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            raw = s
        } else if let i = try? c.decode(Int64.self) {
            raw = String(i)
        } else if let d = try? c.decode(Double.self) {
            raw = (d == d.rounded() && abs(d) < 1e15) ? String(Int64(d)) : String(d)
        } else if let b = try? c.decode(Bool.self) {
            raw = b ? "1" : "0"
        } else {
            raw = ""
        }
    }
}

// MARK: - 赛程 / 比赛

public struct ScheduleRoot: Decodable, Sendable {
    public let scheduleListStats: ScheduleStats?
    public let gameList: [ScheduleDay]?
}

public struct ScheduleStats: Decodable, Sendable {
    public let earliestDate: String?
    public let latestDate: String?
    public let currentDate: String?
    public let anchorMatchId: String?
}

public struct ScheduleDay: Decodable, Sendable, Identifiable {
    public let day: String?      // "20261004"
    public let dayBlock: String? // "10月4日 周日"
    public let matchList: [Match]?

    public var id: String { day ?? UUID().uuidString }
    public var matches: [Match] { matchList ?? [] }
}

/// 赛程条目与 matchInfo 返回同一套字段，统一用这一个模型
public struct Match: Decodable, Sendable, Hashable, Identifiable {
    public let matchId: String?
    public let matchStatus: String?          // NOTSTARTED / IN_PLAY / COMPLETED / CANCELLED ...
    public let matchStatusChinese: String?
    public let matchTime: String?            // "2026-05-14 09:00:00"
    public let beginTime: Double?             // unix 秒
    public let chinaStartTime: Double?        // unix 毫秒
    public let currentQuarter: Int?
    public let homeScore: Int?
    public let awayScore: Int?
    public let homeTeamId: String?
    public let awayTeamId: String?
    public let homeTeamName: String?
    public let awayTeamName: String?
    public let homeTeamEngName: String?
    public let awayTeamEngName: String?
    public let homeTeamLogo: String?
    public let awayTeamLogo: String?
    public let homeTeamDayColor: String?
    public let awayTeamDayColor: String?
    public let homeTeamNightColor: String?
    public let awayTeamNightColor: String?
    public let homeRank: String?
    public let awayRank: String?
    public let competitionStageType: String?
    public let competitionStageDesc: String?
    public let competitionTypeCn: String?
    public let season: String?
    public let round: Int?
    public let matchTvList: [TvChannel]?
    public let winTeamName: String?
    public let iconText: String?
    public let memo: String?
    public let attendance: Int?
    public let arenaCity: String?

    public var id: String { matchId ?? UUID().uuidString }

    public var status: MatchStatus {
        switch matchStatus {
        case "IN_PLAY", "halftime": return .inPlay
        case "COMPLETED": return .finished
        case "NOTSTARTED", "SCHEDULED": return .notStarted
        case "CANCELLED": return .cancelled
        case "POSTPONED": return .postponed
        default: return matchStatus.map { .other($0) } ?? .notStarted
        }
    }

    public var isLive: Bool { status == .inPlay }
    public var isFinished: Bool { status == .finished }

    /// 开赛时间（优先北京时间字符串，其次 unix 秒）
    public var startTime: Date? {
        if let s = matchTime {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f.locale = Locale(identifier: "zh_CN")
            if let d = f.date(from: s) { return d }
        }
        if let t = beginTime { return Date(timeIntervalSince1970: t) }
        return nil
    }
}

public enum MatchStatus: Hashable, Sendable {
    case inPlay
    case finished
    case notStarted
    case cancelled
    case postponed
    case other(String)
}

public struct TvChannel: Decodable, Sendable, Hashable {
    public let tvName: String?
    public let tvUrl: String?
}

// MARK: - 文字直播

public struct LiveFeed: Decodable, Sendable {
    public let home_score: Int?
    public let away_score: Int?
    public let match_id: String?
    public let live: [PlayByPlay]?

    public var plays: [PlayByPlay] { live ?? [] }
}

public struct PlayByPlay: Decodable, Sendable, Hashable, Identifiable {
    public let section: Int?        // 节次
    public let vs: String?          // 该时刻比分 "100-84"
    public let event: String?       // 中文事件描述
    public let event_type: Int?
    public let left_time: String?   // 本节剩余时间
    public let score_change: Int?
    public let player_id: String?
    public let team_id: String?
    public let shot_coord_x: Double?
    public let shot_coord_y: Double?
    public let sequence_id: Double?

    public var id: Double { sequence_id ?? 0 }
}

// MARK: - 技术统计（boxscore / 两队对比）

public struct Boxscore: Decodable, Sendable {
    public let players: [BoxscoreEntry]?
    public let staffs: [BoxscoreEntry]?

    public var roster: [BoxscoreEntry] { players ?? [] }
    public var officials: [BoxscoreEntry] { staffs ?? [] }

    /// 一场比赛的主客队 boxscore 需各请求一次，这里合并成一个列表供 UI 使用
    public init(merged: [BoxscoreEntry], officials: [BoxscoreEntry]) {
        players = merged
        staffs = officials
    }
}

public struct BoxscoreEntry: Decodable, Sendable, Identifiable {
    public let playerOrStaffId: String?
    public let stats: PlayerMatchStats?
    public let tagInfoList: [PlayerTag]?

    public var id: String { playerOrStaffId ?? stats?.playerId ?? UUID().uuidString }
}

public struct PlayerTag: Decodable, Sendable, Hashable {
    public let text: String?
    public let positive: Int?
    public let weight: Int?
}

public struct PlayerMatchStats: Decodable, Sendable {
    public let playerId: String?
    public let teamId: String?
    public let name: String?
    public let alias: String?
    public let number: String?
    public let position: String?
    public let logoUrl: String?
    public let photo: String?
    public let mins: FlexString?      // "35:49"
    public let pts: Int?
    public let reb: Int?
    public let asts: Int?
    public let stl: Int?
    public let blk: Int?
    public let to: Int?
    public let oreb: Int?
    public let dreb: Int?
    public let pf: Int?
    public let plusMinus: FlexString?  // "-5"
    public let twoPoints: FlexString?  // "命中-出手"
    public let threePoints: FlexString?
    public let ft: FlexString?
    public let fgp: FlexString?         // "34.6%"
    public let tpp: FlexString?
    public let ftp: FlexString?
    public let efgp: FlexString?
    public let starter: Int?
    public let onCourt: Int?
    public let dnp: Int?

    public var isStarter: Bool { starter == 1 }
    public var isOnCourt: Bool { onCourt == 1 }
    public var didNotPlay: Bool { dnp == 1 }
}

public struct TeamMatchStats: Decodable, Sendable {
    public let matchId: String?
    public let matchStatus: String?
    public let homeTeamId: String?
    public let awayTeamId: String?
    public let homeTeamName: String?
    public let awayTeamName: String?
    public let homeTeamLogo: String?
    public let awayTeamLogo: String?
    public let homeTeamDayColor: String?
    public let awayTeamDayColor: String?
    public let homeScore: Int?
    public let awayScore: Int?
    public let data: [StatCompare]?

    public var compares: [StatCompare] { data ?? [] }
}

public struct StatCompare: Decodable, Sendable, Hashable, Identifiable {
    public let type: String?
    public let name: String?
    public let home: FlexString?
    public let away: FlexString?
    public let homeVal: Double?
    public let awayVal: Double?

    public var id: String { type ?? name ?? UUID().uuidString }
}

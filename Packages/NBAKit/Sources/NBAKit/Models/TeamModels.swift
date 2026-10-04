import Foundation

// MARK: - 战绩

public struct StandingRoot: Decodable, Sendable {
    public let competitionSeasonStageType: SeasonStageInfo?
    public let rankTypeListMap: [String: [TeamStanding]]?
    public let divRankTypeListMap: [String: [TeamStanding]]?

    public var east: [TeamStanding] { rankTypeListMap?["E"] ?? [] }
    public var west: [TeamStanding] { rankTypeListMap?["W"] ?? [] }
    public var season: String? { competitionSeasonStageType?.competitionSeasonType?.season }
    public var stageDesc: String? { competitionSeasonStageType?.competitionStageTypeName }
}

public struct SeasonStageInfo: Decodable, Sendable {
    public let competitionSeasonType: SeasonType?
    public let competitionStageTypeName: String?
}

public struct SeasonType: Decodable, Sendable {
    public let competitionType: LeagueNames?
    public let season: String?
}

public struct LeagueNames: Decodable, Sendable {
    public let leagueTypeName: String?
    public let competitionTypeName: String?
}

public struct TeamStanding: Decodable, Sendable, Hashable, Identifiable {
    public let rank: Int?
    public let teamId: String?
    public let teamName: String?
    public let teamShortName: String?
    public let logoLink: String?
    public let won: Int?
    public let lost: Int?
    public let winRate: FlexString?
    public let gb: FlexString?
    public let divGb: FlexString?
    public let homeWins: Int?
    public let homeLosses: Int?
    /// 接口不直接返回客场战绩：away = conf(联盟总) - home
    public let confWins: Int?
    public let confLosses: Int?
    public let divWins: Int?
    public let divLosses: Int?
    public let strk: FlexString?
    public let integral: FlexString?
    public let rankTypeDesc: String?

    public var id: String { teamId ?? UUID().uuidString }
    public var record: String { "\(won ?? 0)-\(lost ?? 0)" }

    public var awayWins: Int? {
        guard let conf = confWins, let home = homeWins else { return nil }
        return conf - home
    }

    public var awayLosses: Int? {
        guard let conf = confLosses, let home = homeLosses else { return nil }
        return conf - home
    }
}

// MARK: - 球队资料 / 阵容

public struct TeamBasicInfo: Decodable, Sendable {
    public let teamId: String?
    public let name: String?
    public let full_name: String?
    public let eng_name: String?
    public let teamShortName: String?
    public let city: String?
    public let conference: String?      // E / W
    public let cn_division: String?
    public let eng_division: String?
    public let found_year: Int?
    public let chief_coach: String?
    public let country: String?
    public let dayColor: String?
    public let nightColor: String?
    public let logoLink: String?
    public let picture: String?
    public let intro: String?
    public let leagueType: String?
    public let homepage_link: String?

    public var conferenceName: String? {
        switch conference {
        case "E": return "东部联盟"
        case "W": return "西部联盟"
        default: return conference
        }
    }
}

public struct TeamRosterRoot: Decodable, Sendable {
    public let info: TeamRosterInfo?
    public let list: [RosterPlayer]?

    public var players: [RosterPlayer] { list ?? [] }
}

public struct TeamRosterInfo: Decodable, Sendable {
    public let teamId: String?
    public let name: String?
    public let full_name: String?
    public let en_name: String?
    public let arena: String?
    public let arena_title: String?
    public let logo_link: String?
}

public struct RosterPlayer: Decodable, Sendable, Hashable, Identifiable {
    public let playerId: String?
    public let player_id: Double?
    public let player_name: String?
    public let player_header: String?
    public let player_header_big: String?
    public let number: String?
    public let position: String?
    public let salary: FlexString?
    public let salary_str: FlexString?
    public let is_injured: Int?
    public let min: FlexString?
    public let pts: FlexString?
    public let reb: FlexString?
    public let asts: FlexString?
    public let stl: FlexString?
    public let blk: FlexString?
    public let fgp: FlexString?
    public let tpp: FlexString?
    public let ftp: FlexString?
    public let oreb: FlexString?
    public let dreb: FlexString?
    public let to: FlexString?
    public let pf: FlexString?
    public let homeUrl: String?

    public var id: String { playerId ?? "\(player_id ?? 0)" }
    public var isInjured: Bool { is_injured == 1 }
}

// MARK: - 球队荣誉 / 退役球衣 / 队史纪录

public struct TeamAwardRoot: Decodable, Sendable {
    public let teamInfo: TeamBasicInfo?
    public let awardInfoList: [TeamAward]?

    public var awards: [TeamAward] { awardInfoList ?? [] }
}

public struct TeamAward: Decodable, Sendable, Hashable, Identifiable {
    public let teamAwardType: String?
    public let cnTeamAwardType: String?
    public let seasonList: [FlexString]?

    public var id: String { teamAwardType ?? cnTeamAwardType ?? UUID().uuidString }
    public var seasons: [String] { (seasonList ?? []).map(\.raw) }
}

public struct RetiredRoot: Decodable, Sendable {
    public let teamInfo: TeamBasicInfo?
    public let PlayerRetired: [RetiredJersey]?
    public let OfficialRetired: [RetiredJersey]?
    /// 实测是 { shirtColor, fontColor } 字典而非数组，用 lenient 兜底两种形状
    public let shirtRetiredColors: ShirtColors?

    public var players: [RetiredJersey] { PlayerRetired ?? [] }
    public var officials: [RetiredJersey] { OfficialRetired ?? [] }
}

/// 兼容两种历史形状：字典 {shirtColor,fontColor} / 字符串数组
public struct ShirtColors: Decodable, Sendable {
    public let shirtColor: String?
    public let fontColor: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let map = try? c.decode([String: String?].self) {
            shirtColor = map["shirtColor"] ?? nil
            fontColor = map["fontColor"] ?? nil
        } else {
            shirtColor = nil
            fontColor = nil
        }
    }
}

public struct RetiredJersey: Decodable, Sendable, Hashable, Identifiable {
    public let legacyID: String?
    public let retireId: String?
    public let player_name: String?
    public let shirt_number: FlexString?
    public let positionZhName: String?
    public let careertime: FlexString?
    public let retiredtime: FlexString?
    public let retireRoleNameList: [FlexString]?
    public let homeUrl: String?

    public var roles: [String] { (retireRoleNameList ?? []).map(\.raw) }
    public var id: String { legacyID ?? retireId ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case legacyID = "id", retireId, player_name, shirt_number, positionZhName,
             careertime, retiredtime, retireRoleNameList, homeUrl
    }
}

public struct TeamHistoryRankRoot: Decodable, Sendable {
    public let teamId: String?
    public let competitionStageList: [HistoryStage]?

    public var stages: [HistoryStage] { competitionStageList ?? [] }
}

public struct HistoryStage: Decodable, Sendable, Identifiable {
    public let competitionName: String?
    public let competitionStageName: String?
    public let itemList: [HistoryMetric]?

    public var id: String { competitionStageName ?? competitionName ?? UUID().uuidString }
    public var metrics: [HistoryMetric] { itemList ?? [] }
}

public struct HistoryMetric: Decodable, Sendable, Identifiable {
    public let itemName: String?
    public let rankItemName: String?
    public let chineseName: String?
    public let precision: Int?
    public let suffix: FlexString?
    public let rankInfoList: [RankEntry]?

    public var id: String { rankItemName ?? itemName ?? UUID().uuidString }
    public var entries: [RankEntry] { rankInfoList ?? [] }
}

public struct RankEntry: Decodable, Sendable, Hashable, Identifiable {
    public let rank: Int?
    public let playerId: String?
    public let playerName: String?
    public let photo: String?
    public let bigPhoto: String?
    public let teamId: String?
    public let teamName: String?
    public let value: FlexString?
    public let sortValue: Double?
    public let pts: FlexString?
    public let reb: FlexString?
    public let ast: FlexString?
    public let linkUrl: String?

    public var id: String { "\(playerId ?? "")-\(rank ?? 0)" }
}

// MARK: - 球队赛季数据 / 球队榜

public struct TeamSeasonStats: Decodable, Sendable {
    public let teamId: String?
    public let season: String?
    public let competitionStageMap: [String: [Metric]]?

    public func metrics(stage: String = "REGULAR") -> [Metric] {
        competitionStageMap?[stage] ?? []
    }
}

/// teamSeasonStatsAllRank：顶层数组，39 项指标清单（菜单），每项 data 仅前若干名
public struct TeamMetric: Decodable, Sendable, Identifiable {
    public let name: String?
    public let rankType: String?
    public let isMore: Bool?
    public let leagueAvgValue: FlexString?
    public let leagueMaxValue: FlexString?
    public let data: [TeamRankRow]?

    public var id: String { rankType ?? name ?? UUID().uuidString }
}

/// teamSeasonStatsRank：单指标完整 30 队榜单（顶层平铺 { name, rankType, data[] }）
public struct TeamMetricRank: Decodable, Sendable {
    public let name: String?
    public let rankType: String?
    public let leagueAvgValue: FlexString?
    public let leagueMaxValue: FlexString?
    public let data: [TeamRankRow]?

    public var rows: [TeamRankRow] { data ?? [] }
}

public struct TeamRankRow: Decodable, Sendable, Hashable, Identifiable {
    public let rank: Int?
    public let teamId: String?
    public let teamName: String?
    public let teamShortName: String?
    public let bbr: String?
    public let engName: String?
    public let logoUrl: String?
    public let value: FlexString?

    public var id: String { teamId ?? UUID().uuidString }
}

// MARK: - 赛季指标（球队/球员通用）

public struct Metric: Decodable, Sendable, Hashable, Identifiable {
    public let name: String?       // "ptsAvg"
    public let cnName: String?     // "得分"
    public let quota: FlexString?   // "118.1"
    public let rank: Int?          // 联盟排名
    public let leagueAvgValue: FlexString?
    public let leagueMaxValue: FlexString?
    public let category: FlexString?

    public var id: String { name ?? cnName ?? UUID().uuidString }
}

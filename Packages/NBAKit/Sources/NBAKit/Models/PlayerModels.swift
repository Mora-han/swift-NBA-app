import Foundation

// MARK: - 球员资料

public struct PlayerInfo: Decodable, Sendable {
    public let playerId: String?
    public let name: String?          // 中文名
    public let alias: String?
    public let eng_name: String?
    public let nick: String?
    public let age: FlexString?
    public let number: FlexString?
    public let country: String?
    public let photo: String?
    public let big_photo: String?
    public let birth_date: String?
    public let height: Double?         // 米（1.93）
    public let weight: FlexString?     // 公斤
    public let position: String?
    public let college_school: String?
    public let high_school: String?
    public let nativePlace: String?
    public let draft_year: Int?
    public let draftRound: Int?
    public let draftPick: Int?
    public let draft_team_id: String?
    public let salary: Double?
    public let salaryRank: Int?
    public let contractDetails: String?
    public let teamName: String?
    public let team_id: String?
    public let teamLogoLink: String?
    public let teamDayColor: String?
    public let teamNightColor: String?
    public let nba_first_year: Int?

    /// 接口 height 单位是米（如 1.88），转成 "188cm"；
    /// 兼容接口偶尔直接给厘米数（>=3 的数值按厘米处理）
    public var heightText: String? {
        guard let h = height, h > 0 else { return nil }
        let cm = h < 3 ? Int((h * 100).rounded()) : Int(h.rounded())
        guard (100...250).contains(cm) else { return nil }
        return "\(cm)cm"
    }
}

public struct LeagueSeasonRoot: Decodable, Sendable {
    public let playerId: String?
    public let leagueSeasonList: [LeagueSeason]?

    public var seasons: [LeagueSeason] { leagueSeasonList ?? [] }

    /// 可选赛季（倒序），首选当前赛季
    public var defaultSeason: String? {
        if let list = seasons.first?.switchSeasonList, let first = list.first { return first.raw }
        return seasons.first?.currentSeason
    }
}

public struct LeagueSeason: Decodable, Sendable, Identifiable {
    public let league: String?
    public let currentSeason: String?
    public let switchSeasonList: [FlexString]?

    public var id: String { league ?? UUID().uuidString }
    public var options: [String] { (switchSeasonList ?? []).map(\.raw) }
}

// MARK: - 赛季数据 / 生涯数据

public struct PlayerSeasonStatsRoot: Decodable, Sendable {
    public let playerId: String?
    public let season: String?
    public let dataDimensionMap: [String: Dimension]?
}

public struct PlayerCareerStatsRoot: Decodable, Sendable {
    public let playerId: String?
    public let anchorCompetitionStageType: String?
    public let dataDimensionMap: [String: Dimension]?
}

public struct Dimension: Decodable, Sendable {
    public let name: String?
    public let cnName: String?
    /// playerSeasonStats 用这个 key：阶段 → [Metric]
    public let competitionStagePackListMap: [String: [Metric]]?
    /// playerCareerStats 用这个 key：阶段 → [Metric]（key 名字不同，值形状一致）
    public let competitionStageTypePackListMap: [String: [Metric]]?

    public func metrics(stage: String = "REGULAR") -> [Metric] {
        competitionStagePackListMap?[stage]
            ?? competitionStageTypePackListMap?[stage]
            ?? []
    }
}

public extension PlayerSeasonStatsRoot {
    /// 取某个阶段的指标（basic/advanced 两个维度）
    func metrics(stage: String = "REGULAR") -> [Metric] {
        let dims = dataDimensionMap ?? [:]
        return ["basic", "advanced"].flatMap { dims[$0]?.metrics(stage: stage) ?? [] }
    }

    func dimensionGroups(stage: String = "REGULAR") -> [(title: String, metrics: [Metric])] {
        let dims = dataDimensionMap ?? [:]
        return ["basic", "advanced"].compactMap { key in
            guard let d = dims[key], !d.metrics(stage: stage).isEmpty else { return nil }
            return (d.cnName ?? d.name ?? key, d.metrics(stage: stage))
        }
    }
}

public extension PlayerCareerStatsRoot {
    /// "basic"=生涯汇总, "max"=生涯最高
    func metrics(dimension: String, stage: String = "REGULAR") -> [Metric] {
        dataDimensionMap?[dimension]?.metrics(stage: stage) ?? []
    }

    var dimensionKeys: [String] { dataDimensionMap.map { Array($0.keys).sorted() } ?? [] }
}

// MARK: - 生涯逐赛季汇总 / 逐场（表格型数据）

public struct PlayerAllSeasonStatsRoot: Decodable, Sendable {
    public let playerId: String?
    public let competitionStageMap: [String: SeasonStageTable]?

    /// classify: "AVG" / "SUM"
    public func table(classify: String) -> StatTable? {
        competitionStageMap?["REGULAR"]?.statsClassifyMap?[classify]
    }
}

public struct SeasonStageTable: Decodable, Sendable {
    public let competitionStage: String?
    public let matchType: String?
    public let statsClassifyMap: [String: StatTable]?
}

public struct PlayerAllMatchStatsRoot: Decodable, Sendable {
    public let playerId: String?
    public let season: String?
    public let classifyList: [FlexString]?
    public let statsClassifyList: [StatTable]?

    public var table: StatTable? { statsClassifyList?.first }
}

public struct StatTable: Decodable, Sendable, Identifiable {
    public let classify: String?
    public let headerStrList: [FlexString]?
    public let statsRowList: [StatRow]?
    public let tableHeaderFieldList: [StatTableColumn]?

    public var id: String { classify ?? UUID().uuidString }
    public var headers: [String] { (headerStrList ?? []).map(\.raw) }
    public var rows: [StatRow] { statsRowList ?? [] }
}

public struct StatTableColumn: Decodable, Sendable {
    public let fieldCnName: String?
    public let navigationPath: String?
    public let order: String?
}

public struct StatRow: Decodable, Sendable, Hashable {
    public let quotaList: [FlexString]?

    public var values: [String] { (quotaList ?? []).map(\.raw) }
}

// MARK: - 奖项

public struct PlayerAwardRoot: Decodable, Sendable {
    public let playerId: String?
    public let awardSummaryList: [PlayerAward]?

    public var awards: [PlayerAward] { awardSummaryList ?? [] }
}

public struct PlayerAward: Decodable, Sendable, Hashable, Identifiable {
    public let awardName: String?
    public let awardDesc: String?
    public let awardDetailList: [AwardDetail]?

    public var id: String { awardName ?? UUID().uuidString }
    public var details: [AwardDetail] { awardDetailList ?? [] }
}

public struct AwardDetail: Decodable, Sendable, Hashable {
    public let teamId: String?
    public let season: FlexString?
    public let awardDate: FlexString?
    public let awardDateTime: Double?
}

// MARK: - 搜索

public struct SearchGroup: Decodable, Sendable {
    public let data: [SearchPlayer]?
    public let count: Int?
    public let totalPage: Int?

    public var players: [SearchPlayer] { data ?? [] }
}

public struct SearchPlayer: Decodable, Sendable, Hashable, Identifiable {
    public let playerId: String?
    public let chineseName: String?
    public let englishName: String?
    public let teamName: String?
    public let teamId: String?
    public let position: String?
    public let number: FlexString?
    public let img: String?
    public let country: String?

    public var id: String { playerId ?? UUID().uuidString }
    public var displayName: String { (chineseName ?? englishName ?? "").strippingHTML() }
}

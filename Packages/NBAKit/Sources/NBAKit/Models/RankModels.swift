import Foundation

// MARK: - 球员榜单（一次返回基础+进阶全部指标）

public struct PlayerSeasonRankRoot: Decodable, Sendable {
    public let competitionSeasonStageType: SeasonStageInfo?
    public let dimensionList: [RankDimension]?

    /// 按维度顺序展开的全部指标榜
    public var metrics: [RankMetric] { (dimensionList ?? []).flatMap(\.items) }
}

public struct RankDimension: Decodable, Sendable, Identifiable {
    public let chineseName: String?
    public let engName: String?
    public let itemList: [RankMetric]?

    public var id: String { engName ?? chineseName ?? UUID().uuidString }
    public var items: [RankMetric] { itemList ?? [] }
}

public struct RankMetric: Decodable, Sendable, Identifiable {
    public let chineseName: String?   // "得分"
    public let engName: String?       // "basic.ptsAvg"
    public let rankInfoList: [PlayerRankRow]?

    public var id: String { engName ?? chineseName ?? UUID().uuidString }
    public var rows: [PlayerRankRow] { rankInfoList ?? [] }
}

public struct PlayerRankRow: Decodable, Sendable, Hashable, Identifiable {
    public let rank: Int?
    public let playerId: String?
    public let playerName: String?
    public let photo: String?
    public let bigPhoto: String?
    public let value: FlexString?      // "33.0"
    public let teamId: String?
    public let teamName: String?
    public let teamShortName: String?
    public let pts: FlexString?
    public let reb: FlexString?
    public let ast: FlexString?
    public let stl: FlexString?
    public let homeUrl: String?

    public var id: String { playerId ?? "\(playerName ?? "")-\(rank ?? 0)" }
}

// MARK: - 历史选秀（1970-2026）

public struct DraftRoot: Decodable, Sendable {
    public let draftMap: [String: [DraftPick]]?

    /// 按轮次序号排序
    public var rounds: [(round: String, picks: [DraftPick])] {
        (draftMap ?? [:])
            .sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
            .map { ($0.key, $0.value.sorted { $0.rank ?? 0 < $1.rank ?? 0 }) }
    }
}

public struct DraftPick: Decodable, Sendable, Hashable, Identifiable {
    public let round: Int?
    public let rank: Int?
    public let playerId: String?
    public let playerName: String?
    public let photo: String?
    public let bigPhoto: String?
    public let position: String?
    public let height: Int?             // cm
    public let draftTeamName: String?
    public let teamName: String?
    public let careerInfoMap: [String: DraftCareer]?

    public var id: String { "\(round ?? 0)-\(rank ?? 0)" }

    public var nbaCareer: DraftCareer? { careerInfoMap?["NBA"] }
}

public struct DraftCareer: Decodable, Hashable, Sendable {
    public let careerPts: FlexString?
    public let careerReb: FlexString?
    public let careerAst: FlexString?
}

// MARK: - 历史荣誉（MVP / 总冠军 / 各单项 历届得主）

public struct AllAwardsRoot: Decodable, Sendable {
    public let playerAwardMapDTOList: [AwardCategory]?

    public var categories: [AwardCategory] { playerAwardMapDTOList ?? [] }
}

public struct AwardCategory: Decodable, Sendable, Identifiable {
    public let awardName: String?    // "NBA_Most_Valuable_Player"
    public let awardDesc: String?    // "MVP"
    public let playerAwardDetailDTOList: [AwardWinner]?

    public var id: String { awardName ?? UUID().uuidString }
    public var winners: [AwardWinner] { playerAwardDetailDTOList ?? [] }

    /// 去重后的得主人数（同一球员多赛季获奖只算一次）
    public var winnerCount: Int {
        Set(winners.compactMap(\.playerId)).count
    }
}

public struct AwardWinner: Decodable, Sendable, Hashable, Identifiable {
    public let playerId: String?
    public let playerName: String?
    public let photo: String?
    public let bigPhoto: String?
    public let teamId: String?
    public let teamName: String?
    public let season: String?        // "2025-2026"
    public let awardDate: String?
    public let awardName: String?
    public let awardDesc: String?
    public let pts: Double?
    public let reb: Double?
    public let asts: Double?

    public var id: String {
        "\(playerId ?? "")-\(season ?? "")-\(awardDate ?? "")-\(awardName ?? "")"
    }
}

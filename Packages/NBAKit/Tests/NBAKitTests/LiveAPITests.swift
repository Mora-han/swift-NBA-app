import XCTest
@testable import NBAKit

/// 全量真实接口解码测试：逐个调用 App 用到的接口并断言关键字段。
/// 跑 `swift test` 即可验证「代码 100% 对齐线上真实响应」（需要网络）。
final class LiveAPITests: XCTestCase {
    private let api = HupuClient.shared

    private func completedMatch() async throws -> (matchId: String, teamId: String) {
        let root: ScheduleRoot = try await api.fetch(.scheduleList(day: nil))
        let days = root.gameList ?? []
        let match = days.flatMap(\.matches).first { $0.isFinished && $0.matchId != nil }
        return (try XCTUnwrap(match?.matchId), try XCTUnwrap(match?.homeTeamId))
    }

    // MARK: 比赛

    func testScheduleList() async throws {
        let root: ScheduleRoot = try await api.fetch(.scheduleList(day: nil))
        let matches = (root.gameList ?? []).flatMap(\.matches)
        XCTAssertFalse(matches.isEmpty)
        XCTAssertFalse(try XCTUnwrap(matches.first?.matchId).isEmpty)
        XCTAssertNotNil(root.scheduleListStats?.currentDate)
    }

    func testMatchInfo() async throws {
        let (id, _) = try await completedMatch()
        let info: Match = try await api.fetch(.matchInfo(matchId: id))
        XCTAssertEqual(info.matchId, id)
        XCTAssertNotNil(info.homeTeamName)
        XCTAssertNotNil(info.homeScore)
    }

    func testLiveFeed() async throws {
        let (id, _) = try await completedMatch()
        let feed: LiveFeed = try await api.fetch(.live(matchId: id))
        XCTAssertFalse(feed.plays.isEmpty)
        XCTAssertNotNil(feed.plays.first?.event)
    }

    func testBoxscore() async throws {
        let (id, team) = try await completedMatch()
        let box: Boxscore = try await api.fetch(.boxscore(matchId: id, teamId: team))
        let players = box.roster
        XCTAssertFalse(players.isEmpty)
        let stats = try XCTUnwrap(players.first(where: { $0.stats != nil })?.stats)
        XCTAssertNotNil(stats.name)
        XCTAssertNotNil(stats.pts)
    }

    func testTeamMatchStats() async throws {
        let (id, _) = try await completedMatch()
        let stats: TeamMatchStats = try await api.fetch(.teamMatchStats(matchId: id))
        XCTAssertFalse(stats.compares.isEmpty)
        XCTAssertNotNil(stats.compares.first?.name)
    }

    // MARK: 战绩与球队榜

    /// 历年战绩：指定赛季应返回该赛季排名（用于「战绩」页的历史切换）
    func testHistoricalStandings() async throws {
        for season in ["2025-2026", "2024-2025", "2023-2024"] {
            let root: StandingRoot = try await api.fetch(.teamStanding(stage: "REGULAR", season: season))
            XCTAssertEqual(root.season, season, "应返回请求的赛季")
            XCTAssertFalse(root.east.isEmpty, "\(season) 东部应有数据")
            XCTAssertFalse(root.west.isEmpty, "\(season) 西部应有数据")
            XCTAssertNotNil(root.east.first?.teamId)
        }
    }

    func testStandings() async throws {
        let root: StandingRoot = try await api.fetch(.teamStandingList)
        XCTAssertFalse(root.east.isEmpty)
        XCTAssertFalse(root.west.isEmpty)
        XCTAssertNotNil(root.season)
        XCTAssertNotNil(root.east.first?.teamId)
        XCTAssertNotNil(root.east.first?.won)
    }

    func testTeamStatRank() async throws {
        let season = await SeasonProvider.shared.currentSeason()
        let rank: TeamMetricRank = try await api.fetch(
            .teamSeasonStatsRank(rankType: "ptsAvg", season: season))
        XCTAssertEqual(rank.rows.count, 30, "单指标球队榜应为 30 队")
        XCTAssertNotNil(rank.rows.first?.teamId)
    }

    func testTeamStatAllRankMenu() async throws {
        let metrics: [TeamMetric] = try await api.fetch(.teamSeasonStatsAllRank)
        XCTAssertGreaterThanOrEqual(metrics.count, 30)
        XCTAssertFalse(try XCTUnwrap(metrics.first(where: { $0.rankType != nil })?.rankType ?? "").isEmpty)
    }

    // MARK: 球队

    private var lakersId: String {
        TeamRegistry.all.first { $0.name == "湖人" }?.teamId ?? "1901000000501323"
    }

    func testTeamBasicInfo() async throws {
        let info: TeamBasicInfo = try await api.fetch(.teamBasicInfo(teamId: lakersId))
        XCTAssertEqual(info.teamId, lakersId)
        XCTAssertNotNil(info.name)
        XCTAssertNotNil(info.conference)
    }

    func testTeamRoster() async throws {
        let root: TeamRosterRoot = try await api.fetch(.teamPlayerList(teamId: lakersId))
        XCTAssertFalse(root.players.isEmpty)
        XCTAssertNotNil(root.players.first?.player_name)
    }

    func testTeamSeasonStats() async throws {
        let season = await SeasonProvider.shared.currentSeason()
        let stats: TeamSeasonStats = try await api.fetch(.teamSeasonStats(teamId: lakersId, season: season))
        XCTAssertFalse(stats.metrics().isEmpty)
        XCTAssertNotNil(stats.metrics().first?.cnName)
    }

    func testTeamAwards() async throws {
        let root: TeamAwardRoot = try await api.fetch(.teamAwardList(teamId: lakersId))
        XCTAssertFalse(root.awards.isEmpty)
        XCTAssertNotNil(root.awards.first?.cnTeamAwardType)
    }

    func testTeamRetiredJerseys() async throws {
        let root: RetiredRoot = try await api.fetch(.teamShirtRetired(teamId: lakersId))
        XCTAssertFalse(root.players.isEmpty)
        XCTAssertNotNil(root.players.first?.shirt_number?.raw)
    }

    func testTeamHistoryRanks() async throws {
        let root: TeamHistoryRankRoot = try await api.fetch(.teamHistoryPlayerStatsRank(teamId: lakersId))
        XCTAssertFalse(root.stages.isEmpty)
        XCTAssertFalse(try XCTUnwrap(root.stages.first?.metrics).isEmpty)
    }

    func testTeamSchedule() async throws {
        let root: ScheduleRoot = try await api.fetch(.teamScheduleList(teamId: lakersId))
        XCTAssertNotNil(root.gameList, "单队赛程应返回 gameList（休赛期可能为空数组）")
    }

    // MARK: 球员

    private var curryId: String { "1901000000442301" }

    func testSearchPlayer() async throws {
        let groups: [SearchGroup] = try await api.fetch(.searchPlayer(name: "库里"))
        let players = groups.flatMap(\.players)
        XCTAssertFalse(players.isEmpty)
        XCTAssertFalse(try XCTUnwrap(players.first?.displayName).isEmpty)
        XCTAssertFalse(try XCTUnwrap(players.first?.englishName ?? "").isEmpty)
    }

    func testPlayerInfo() async throws {
        let info: PlayerInfo = try await api.fetch(.playerInfo(playerId: curryId))
        XCTAssertNotNil(info.name)
        XCTAssertNotNil(info.eng_name)
        XCTAssertNotNil(info.height)
    }

    func testPlayerLeagueSeason() async throws {
        let root: LeagueSeasonRoot = try await api.fetch(.playerLeagueSeason(playerId: curryId))
        XCTAssertFalse(try XCTUnwrap(root.defaultSeason).isEmpty)
    }

    func testPlayerSeasonStats() async throws {
        let seasons: LeagueSeasonRoot = try await api.fetch(.playerLeagueSeason(playerId: curryId))
        let season = try XCTUnwrap(seasons.defaultSeason)
        let root: PlayerSeasonStatsRoot = try await api.fetch(
            .playerSeasonStats(playerId: curryId, season: season, stage: "REGULAR"))
        XCTAssertFalse(root.metrics().isEmpty)
        XCTAssertNotNil(root.metrics().first?.quota?.raw)
    }

    func testPlayerCareerStats() async throws {
        let root: PlayerCareerStatsRoot = try await api.fetch(.playerCareerStats(playerId: curryId))
        XCTAssertFalse(root.metrics(dimension: "basic").isEmpty, "生涯汇总维度应存在")
        XCTAssertFalse(root.dimensionKeys.isEmpty)
    }

    func testPlayerAllSeasonStats() async throws {
        let root: PlayerAllSeasonStatsRoot = try await api.fetch(.playerAllSeasonStats(playerId: curryId))
        let table = try XCTUnwrap(root.table(classify: "AVG"))
        XCTAssertFalse(table.headers.isEmpty)
        XCTAssertFalse(table.rows.isEmpty)
        XCTAssertEqual(table.headers.count, table.rows.first?.values.count)
    }

    func testPlayerGameLog() async throws {
        let seasons: LeagueSeasonRoot = try await api.fetch(.playerLeagueSeason(playerId: curryId))
        let season = try XCTUnwrap(seasons.defaultSeason)
        let root: PlayerAllMatchStatsRoot = try await api.fetch(
            .playerAllMatchStats(playerId: curryId, season: season, stage: "REGULAR"))
        let table = try XCTUnwrap(root.table)
        XCTAssertFalse(table.headers.isEmpty)
        XCTAssertFalse(table.rows.isEmpty)
    }

    func testPlayerAwards() async throws {
        let root: PlayerAwardRoot = try await api.fetch(.playerAwardList(playerId: curryId))
        XCTAssertFalse(root.awards.isEmpty)
        XCTAssertNotNil(root.awards.first?.awardDesc)
    }

    func testPlayerSeasonRank() async throws {
        let season = await SeasonProvider.shared.currentSeason()
        let root: PlayerSeasonRankRoot = try await api.fetch(.playerSeasonRank(season: season))
        let metrics = root.metrics
        XCTAssertFalse(metrics.isEmpty, "榜单指标应 ≥32 项")
        let firstWithData = metrics.first { !$0.rows.isEmpty }
        XCTAssertNotNil(firstWithData, "至少一项指标应有排名数据")
        XCTAssertNotNil(firstWithData?.rows.first?.playerId)
    }

    // MARK: 百科

    func testDraftYears() async throws {
        let years: [String] = try await api.fetch(.draftYears)
        XCTAssertGreaterThanOrEqual(years.count, 50)
        XCTAssertTrue(years.contains("2024"))
    }

    func testDraftList() async throws {
        let root: DraftRoot = try await api.fetch(.draft(year: "2024"))
        let rounds = root.rounds
        XCTAssertFalse(rounds.isEmpty)
        let first = try XCTUnwrap(rounds.first?.picks.first)
        XCTAssertNotNil(first.playerName)
        XCTAssertEqual(first.rank, 1)
    }

    func testAllPlayerAwards() async throws {
        let season = await SeasonProvider.shared.currentSeason()
        let root: AllAwardsRoot = try await api.fetch(.allPlayerAwardList(season: season))
        XCTAssertGreaterThanOrEqual(root.categories.count, 10)
        XCTAssertFalse(try XCTUnwrap(root.categories.first?.winners).isEmpty)
    }

    // MARK: 基础设施

    func testSeasonProvider() async throws {
        let season = await SeasonProvider.shared.currentSeason()
        XCTAssertEqual(season.count, 9)
        XCTAssertNotNil(SeasonUtility.offset(season, by: -1))
    }

    func testTeamRegistry() {
        XCTAssertEqual(TeamRegistry.all.count, 30)
        XCTAssertNotNil(TeamRegistry.all.first { $0.name == "湖人" })
    }

    func testHTTPLinkUpgrade() {
        let url = HupuMedia.imageURL("http://i11.hoopchina.com.cn/a.png")
        XCTAssertEqual(url?.absoluteString.hasPrefix("https://"), true)
        XCTAssertNil(HupuMedia.imageURL(nil))
    }

    func testHeightFormatting() {
        // 1.88m → 188cm；接口偶尔直接给 188 → 188cm
        for raw in [1.88, 2.06, 188.0, 206.0] {
            let info = PlayerInfo(playerId: nil, name: nil, alias: nil, eng_name: nil, nick: nil,
                                  age: nil, number: nil, country: nil, photo: nil, big_photo: nil,
                                  birth_date: nil, height: raw, weight: nil, position: nil,
                                  college_school: nil, high_school: nil, nativePlace: nil,
                                  draft_year: nil, draftRound: nil, draftPick: nil,
                                  draft_team_id: nil, salary: nil, salaryRank: nil,
                                  contractDetails: nil, teamName: nil, team_id: nil,
                                  teamLogoLink: nil, teamDayColor: nil, teamNightColor: nil,
                                  nba_first_year: nil)
            XCTAssertNotNil(info.heightText, "height=\(raw) 应能格式化")
        }
        XCTAssertEqual(PlayerInfo(playerId: nil, name: nil, alias: nil, eng_name: nil, nick: nil,
                                  age: nil, number: nil, country: nil, photo: nil, big_photo: nil,
                                  birth_date: nil, height: 1.88, weight: nil, position: nil,
                                  college_school: nil, high_school: nil, nativePlace: nil,
                                  draft_year: nil, draftRound: nil, draftPick: nil,
                                  draft_team_id: nil, salary: nil, salaryRank: nil,
                                  contractDetails: nil, teamName: nil, team_id: nil,
                                  teamLogoLink: nil, teamDayColor: nil, teamNightColor: nil,
                                  nba_first_year: nil).heightText, "188cm")
        XCTAssertEqual(PlayerInfo(playerId: nil, name: nil, alias: nil, eng_name: nil, nick: nil,
                                  age: nil, number: nil, country: nil, photo: nil, big_photo: nil,
                                  birth_date: nil, height: nil, weight: nil, position: nil,
                                  college_school: nil, high_school: nil, nativePlace: nil,
                                  draft_year: nil, draftRound: nil, draftPick: nil,
                                  draft_team_id: nil, salary: nil, salaryRank: nil,
                                  contractDetails: nil, teamName: nil, team_id: nil,
                                  teamLogoLink: nil, teamDayColor: nil, teamNightColor: nil,
                                  nba_first_year: nil).heightText, nil)
    }

    func testHTMLStrip() {
        XCTAssertEqual("斯蒂芬-<font color='#c01e2f'>库里</font>".strippingHTML(), "斯蒂芬-库里")
    }
}

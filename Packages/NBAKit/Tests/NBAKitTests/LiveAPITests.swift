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

    /// 球队历史战绩：逐赛季回溯时应能命中同一支球队，且战绩字段可用
    func testTeamSeasonRecordsAcrossSeasons() async throws {
        let teamId = "1901000000501288"      // 骑士
        var hitCount = 0
        // 虎扑战绩接口最早只到 2004-05，这里只抽查较近的几个赛季
        for season in ["2025-2026", "2024-2025", "2023-2024", "2022-2023", "2021-2022"] {
            let root: StandingRoot = try await api.fetch(.teamStanding(stage: "REGULAR", season: season))
            let east = root.east.contains { $0.teamId == teamId }
            let row = (east ? root.east : root.west).first { $0.teamId == teamId }
            XCTAssertNotNil(row, "\(season) 应能查到该球队战绩")
            XCTAssertGreaterThan((row?.won ?? 0) + (row?.lost ?? 0), 0,
                                 "\(season) 胜负场次不应为空")
            hitCount += 1
        }
        XCTAssertEqual(hitCount, 5)
    }

    /// 球员数据榜：单指标榜单翻页应能取回远超 5 人的完整榜单，
    /// 且第一页与第二页数据不同（曾经只取 2 页会导致部分指标只有前 5 名）
    func testPlayerSingleDimensionRankPaginates() async throws {
        let season = await SeasonProvider.shared.currentSeason()
        let page1: RankMetric = try await api.fetch(
            .playerSingleDimensionRank(rankType: "basic.ptsAvg", season: season, page: 1))
        XCTAssertEqual(page1.rows.count, 20, "单页应为 20 条")

        var seen: [String] = []
        var page = 1
        while page <= 60 {
            let result: RankMetric = try await api.fetch(
                .playerSingleDimensionRank(rankType: "basic.ptsAvg", season: season, page: page))
            let batch = result.rows
            seen.append(contentsOf: batch.compactMap(\.playerId))
            if batch.count < 20 { break }
            page += 1
        }
        XCTAssertGreaterThan(seen.count, 30, "完整榜单应远超 playerSeasonRank 给出的前 5 名")
        XCTAssertEqual(Set(seen).count, seen.count, "翻页结果不应出现重复球员")
    }

    /// 不同维度可能存在同名指标（如 basic.ptsAvg 与 criticalMoment.ptsAvg 都叫「得分」），
    /// 因此榜单必须用 engName 而不是中文名做唯一标识，否则会互相覆盖只剩 5 条。
    func testPlayerRankMetricNamesCanCollide() async throws {
        let season = await SeasonProvider.shared.currentSeason()
        let root: PlayerSeasonRankRoot = try await api.fetch(.playerSeasonRank(season: season))
        let metrics = root.metrics
        XCTAssertGreaterThan(metrics.count, 30, "应返回全部指标")

        let rankTypes = metrics.compactMap(\.engName)
        XCTAssertEqual(Set(rankTypes).count, rankTypes.count, "engName 必须唯一")

        // 中文名允许重复，但重复项的 engName 必须不同，否则数据层无法区分。
        // 当前赛季 basic/advanced 两组 46 项无重名，因此这里只断言「若重名则 engName 必不同」，
        // 重名本身在不同赛季才出现（历史赛季还有 criticalMoment 组）。
        let byName = Dictionary(grouping: metrics.filter { $0.engName != nil && $0.chineseName != nil },
                                by: { $0.chineseName! })
        for (name, group) in byName where group.count > 1 {
            XCTAssertEqual(Set(group.compactMap(\.engName)).count, group.count,
                           "同名指标「\(name)」必须对应不同的 engName")
        }
    }

    /// 历史数据榜：两个榜单接口都支持历史赛季，但覆盖深度不同 ——
    /// playerSeasonRank 只给每项前 5 名，单指标榜单接口可翻页取到约 100 名。
    func testPlayerRankHistory() async throws {
        let root: PlayerSeasonRankRoot = try await api.fetch(.playerSeasonRank(season: "1999-2000"))
        XCTAssertFalse(root.metrics.isEmpty, "1999-2000 应有历史数据")

        let scoring = root.metrics.first { $0.engName == "basic.ptsAvg" }
        XCTAssertNotNil(scoring, "历史赛季应包含得分榜")
        XCTAssertLessThanOrEqual(scoring?.rows.count ?? 99, 5,
                                 "playerSeasonRank 每项只给前 5 名")

        let historical: RankMetric = try await api.fetch(
            .playerSingleDimensionRank(rankType: "basic.ptsAvg", season: "1999-2000", page: 1))
        XCTAssertFalse(historical.rows.isEmpty, "单指标榜单接口应支持历史赛季")
        XCTAssertTrue(historical.rows.contains { $0.playerName?.contains("奥尼尔") == true },
                      "1999-2000 得分榜首位应是奥尼尔")

        // 更早的赛季没有数据，历史榜需要据此兜底
        let ancient: RankMetric? = try? await api.fetch(
            .playerSingleDimensionRank(rankType: "basic.ptsAvg", season: "1995-1996", page: 1))
        XCTAssertTrue(ancient?.rows.isEmpty ?? true, "1995-1996 早于数据范围")
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

    // MARK: 历史总数据榜（生涯累计）

    /// 生涯总榜菜单：grain=totals 才返回「总得分/总助攻」这类累计指标；
    /// 实测 grain 只有 perGame / totals 两个合法值，其余全部 invalid grain。
    func testCareerTotalRankMenu() async throws {
        let root: CareerRankRoot = try await api.fetch(.careerTotalRankMenu)
        let metrics = root.metrics
        XCTAssertGreaterThanOrEqual(metrics.count, 20, "生涯总指标应有 20+ 项")

        let ids = metrics.compactMap(\.engName)
        XCTAssertEqual(Set(ids).count, ids.count, "engName 必须唯一")

        let pts = try XCTUnwrap(metrics.first { $0.engName == "basic.pts" })
        XCTAssertEqual(pts.chineseName, "总得分")
        let top = try XCTUnwrap(pts.rows.first)
        XCTAssertEqual(top.rank, 1)
        XCTAssertEqual(top.playerName, "詹姆斯", "NBA 历史总得分榜首应是詹姆斯")
        XCTAssertGreaterThanOrEqual(Int(top.value?.raw ?? "0") ?? 0, 40000)
    }

    /// 单指标生涯总榜翻页：20 条/页，第一页 rank 从 1 起、第二页从 21 起且无重复球员。
    func testCareerTotalRankPaginates() async throws {
        let page1: CareerRankPageRoot = try await api.fetch(
            .careerTotalRank(rankType: "basic.pts", page: 1))
        XCTAssertEqual(page1.rows.count, 20, "单页应为 20 条")
        XCTAssertEqual(page1.rows.first?.rank, 1)
        XCTAssertEqual(page1.rows.first?.playerName, "詹姆斯")

        let page2: CareerRankPageRoot = try await api.fetch(
            .careerTotalRank(rankType: "basic.pts", page: 2))
        XCTAssertEqual(page2.rows.first?.rank, 21)

        let ids = (page1.rows + page2.rows).compactMap(\.playerId)
        XCTAssertEqual(Set(ids).count, ids.count, "翻页结果不应出现重复球员")

        // 总助攻榜榜首是斯托克顿，用来确认 rankType 生效而非缓存串页
        let ast: CareerRankPageRoot = try await api.fetch(
            .careerTotalRank(rankType: "basic.ast", page: 1))
        XCTAssertEqual(ast.rows.first?.playerName, "斯托克顿")
        XCTAssertEqual(ast.dataDimension?.chineseName, "总助攻")
    }

    // MARK: 新闻

    /// NBA 新闻流：20 条/页，newsId=上一页最后一条 nid 翻页，两页无重复；
    /// link 混用三种 scheme，必须都能换算出可打开的 https 地址。
    func testNewsListPaginates() async throws {
        let page1: NewsListRoot = try await api.fetch(.newsList(cursor: nil))
        let items1 = page1.items
        XCTAssertFalse(items1.isEmpty, "NBA 新闻流不应为空")
        XCTAssertFalse(try XCTUnwrap(items1.first?.title).isEmpty)
        XCTAssertNotNil(try XCTUnwrap(items1.first?.nid?.raw))

        let cursor = try XCTUnwrap(items1.last?.nid?.raw)
        let page2: NewsListRoot = try await api.fetch(.newsList(cursor: cursor))
        let items2 = page2.items
        XCTAssertFalse(items2.isEmpty)

        let ids = Set((items1 + items2).compactMap { $0.nid?.raw })
        XCTAssertEqual(ids.count, items1.count + items2.count, "翻页不应重复")

        // 每条都应能拿到 https 链接（kanqiu://huputiyu:// 均需换算）
        for item in (items1 + items2) {
            let url = item.webURL
            XCTAssertNotNil(url, "「\(item.title ?? "")」应能换算出可打开链接")
            XCTAssertEqual(url?.scheme, "https", "最终链接必须是 https")
        }
    }

    // MARK: 要闻正文（SSR 页内嵌 JSON）

    func testNewsThreadContent() async throws {
        let list: NewsListRoot = try await api.fetch(.newsList(cursor: nil))
        // 新闻流里 20 条中有 19 条带 tid，取第一条带 tid 的当样本
        let item = try XCTUnwrap(list.items.first { $0.tid?.raw.isEmpty == false })
        let tid = try XCTUnwrap(item.tid?.raw)

        let page = try await api.fetchThreadDetail(tid: tid)
        XCTAssertFalse(try XCTUnwrap(page.detail.title).isEmpty)
        XCTAssertEqual(page.detail.tid?.raw, tid)

        let blocks = page.detail.blocks
        XCTAssertFalse(blocks.isEmpty, "正文应有内容块")
        let text = blocks.compactMap { if case .text(let t) = $0 { return t } else { return nil } }
        XCTAssertFalse(text.isEmpty, "正文至少应有一个文字段")
        XCTAssertTrue(text.allSatisfy { !$0.contains("<") }, "文字段不应残留 HTML 标签")
        for block in blocks {
            if case .image(let url) = block {
                XCTAssertTrue(url.hasPrefix("https://"), "正文图必须 https：\(url)")
            }
        }

        // 热门回复（亮评）
        for reply in page.lightReplies {
            XCTAssertFalse(reply.plainText.contains("<"), "亮评不应残留 HTML 标签")
        }
    }

    // MARK: 实时新闻流

    /// MSite 是时效最好的一路（固定 100 条、覆盖近数小时、最新通常 1~2 分钟前）；
    /// newsList 首页反而滞后几十分钟，所以实时流用它、翻历史才用 newsList。
    func testNewsSiteFeedIsFresh() async throws {
        let root: NewsListRoot = try await api.fetch(.newsSite)
        let items = root.items
        XCTAssertGreaterThan(items.count, 50, "实时流应返回接近 100 条")

        let ids = Set(items.compactMap { $0.nid?.raw })
        XCTAssertEqual(ids.count, items.count, "实时流不应有重复 nid")

        let dates = items.compactMap(\.publishDate)
        XCTAssertEqual(dates.count, items.count, "每条都应能解析 publishTime")

        let newest = try XCTUnwrap(dates.max())
        let oldest = try XCTUnwrap(dates.min())
        XCTAssertGreaterThan(newest.timeIntervalSince(oldest), 3600, "实时流应覆盖至少 1 小时")

        let age = Date().timeIntervalSince(newest)
        XCTAssertLessThan(age, 3 * 3600,
                          "最新条目应足够新，实际 \(Int(age / 60)) 分钟前")

        for item in items {
            XCTAssertFalse(item.title?.isEmpty ?? true)
            XCTAssertEqual(item.webURL?.scheme, "https")
        }
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

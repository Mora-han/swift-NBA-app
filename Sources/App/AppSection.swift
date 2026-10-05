import SwiftUI

/// 六个主栏目。iOS 用底部 TabBar，macOS 用 AppKit 侧边栏，共用这份定义。
enum AppSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case scores, news, standings, teams, players, encyclopedia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scores: return "比分"
        case .news: return "新闻"
        case .standings: return "战绩"
        case .teams: return "球队"
        case .players: return "球员"
        case .encyclopedia: return "百科"
        }
    }

    var symbol: String {
        switch self {
        case .scores: return "sportscourt"
        case .news: return "newspaper"
        case .standings: return "list.number"
        case .teams: return "shield.lefthalf.filled"
        case .players: return "person.2"
        case .encyclopedia: return "books.vertical"
        }
    }

    /// 该栏目的根视图（命名避开 View 协议的 view()）
    @ViewBuilder
    @MainActor
    func content() -> some View {
        switch self {
        case .scores: ScoresView()
        case .news: NewsView()
        case .standings: StandingsView()
        case .teams: TeamsView()
        case .players: PlayersView()
        case .encyclopedia: EncyclopediaView()
        }
    }
}
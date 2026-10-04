import SwiftUI
import NBAKit

@main
struct NBAApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}

/// 根标签页：iPhone 用系统 TabView，iPad/Mac 用系统侧边栏（原生行为，Liquid Glass 自动生效）
struct RootTabView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isWide: Bool {
        #if os(macOS)
        true
        #else
        sizeClass == .regular
        #endif
    }

    var body: some View {
        if isWide {
            TabView {
                Tab("比分", systemImage: "sportscourt") {
                    ScoresView()
                }
                Tab("战绩", systemImage: "list.number") {
                    StandingsView()
                }
                Tab("球队", systemImage: "shield.lefthalf.filled") {
                    TeamsView()
                }
                Tab("球员", systemImage: "person.2") {
                    PlayersView()
                }
                Tab("百科", systemImage: "books.vertical") {
                    EncyclopediaView()
                }
            }
        } else {
            TabView {
                ScoresView()
                    .tabItem { Label("比分", systemImage: "sportscourt") }
                StandingsView()
                    .tabItem { Label("战绩", systemImage: "list.number") }
                TeamsView()
                    .tabItem { Label("球队", systemImage: "shield.lefthalf.filled") }
                PlayersView()
                    .tabItem { Label("球员", systemImage: "person.2") }
                EncyclopediaView()
                    .tabItem { Label("百科", systemImage: "books.vertical") }
            }
        }
    }
}

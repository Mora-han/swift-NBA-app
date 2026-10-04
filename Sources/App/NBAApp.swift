import SwiftUI

@main
struct NBAApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                #if os(macOS)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear {
                    // 临时：开发期把窗口渲染成 PNG 以验证界面，不设置该环境变量时无副作用
                    let path = ProcessInfo.processInfo.environment["NBA_SHOT"]
                    guard let path, !path.isEmpty else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                        Self.captureWindow(to: path)
                    }
                }
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unifiedCompact)
        #endif
    }
}

struct RootView: View {
    var body: some View {
        #if os(macOS)
        MacRootView()
        #else
        CompactRootView()
        #endif
    }
}

// MARK: - iOS / iPadOS：系统底部标签栏

private struct CompactRootView: View {
    var body: some View {
        TabView {
            ForEach(AppSection.allCases) { section in
                section.content()
                    .tabItem { Label(section.title, systemImage: section.symbol) }
            }
        }
    }
}

// MARK: - macOS：NavigationSplitView 侧边栏（macOS 原生 source list，无顶栏）

private struct MacRootView: View {
    @State private var selection: AppSection? = .scores

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            (selection ?? .scores).content()
        }
        // macOS 专属样式：让 TabView 也走侧边栏（本次未使用 TabView，保持显式）
        .navigationSplitViewStyle(.balanced)
    }
}

#if os(macOS)
extension NBAApp {
    /// 把主窗口渲染成 PNG（仅开发期验证界面用）
    static func captureWindow(to path: String) {
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }) else { return }
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
#endif

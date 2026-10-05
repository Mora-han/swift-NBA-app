import SwiftUI

// MARK: - 品牌色 & 排版

extension Color {
    /// 从接口返回的 "RRGGBB" 构造品牌色（球队主题色）
    init(hex string: String?, fallback: Color = .accentColor) {
        if let rgb = string?.hexColorAlpha() {
            self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
        } else {
            self = fallback
        }
    }

    /// 品牌色加深/提亮版本，用于比分条背景渐变
    static func brandShade(_ hex: String?, delta: Double) -> Color {
        guard let rgb = hex?.hexColorAlpha() else { return .accentColor.opacity(0.15) }
        func adjust(_ c: Double) -> Double { max(0, min(1, c + delta)) }
        return Color(.sRGB, red: adjust(rgb.red), green: adjust(rgb.green), blue: adjust(rgb.blue), opacity: 1)
    }
}

enum Theme {
    /// 统一的圆角：iOS 系统卡片为 10~16，这里跟随系统层级
    static let cardRadius: CGFloat = 14
    static let tileRadius: CGFloat = 10
    static let gutter: CGFloat = 16

    /// 页面背景（跟随系统深浅色）
    static var groupedBackground: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var secondaryBackground: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #else
        Color(nsColor: .underPageBackgroundColor)
        #endif
    }

    static var separator: Color {
        #if os(iOS)
        Color(.separator)
        #else
        Color(nsColor: .separatorColor)
        #endif
    }

    /// 卡片底色。系统材质在 iOS/iPadOS 上会参与 Liquid Glass 折射，
    /// 在 iPad 上与窗口底色对比明显，macOS 用控件底色。
    static var cardBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.secondarySystemGroupedBackground)
        #endif
    }

    /// 需要与背景明确区分的容器（比分卡、战绩行等）使用更强的系统材质
    static var raisedBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    static var win: Color { Color(red: 0.18, green: 0.62, blue: 0.32) }
    static var loss: Color { Color(red: 0.83, green: 0.24, blue: 0.24) }
    static var live: Color { Color(red: 0.90, green: 0.22, blue: 0.24) }
}

// MARK: - 通用修饰

extension View {
    /// 系统风格的卡片容器（材质底 + 圆角 + 极淡描边，iPad 上边界清晰）
    func systemCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(Theme.raisedBackground, in: .rect(cornerRadius: Theme.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    /// 列表类容器（战绩行 / 阵容行等）
    func cardSurface() -> some View {
        background(Theme.raisedBackground, in: .rect(cornerRadius: Theme.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            }
            .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }
}

extension View {
    /// iOS/iPadOS 的 inline 标题；macOS 无此概念，原生标题行为已一致
    func inlineNavigationTitle() -> some View {
        #if os(macOS)
        self
        #else
        navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

extension View {
    /// 正文最大宽度。iPad 上不再收窄到 760pt —— 改为铺满可用宽度并靠「自适应列数」
    /// 提升信息密度，宽屏一行可以放下更多卡片。macOS 窗口本身较窄，保留上限。
    func pageWidth(_ max: CGFloat = 1400) -> some View {
        #if os(macOS)
        frame(maxWidth: min(max, 1000))
            .frame(maxWidth: .infinity)
        #else
        frame(maxWidth: max)
            .frame(maxWidth: .infinity)
        #endif
    }

    /// 页面背景（跟随系统深浅色）
    func pageBackground() -> some View {
        #if os(macOS)
        background(Theme.groupedBackground)
        #else
        background(Theme.groupedBackground.ignoresSafeArea())
        #endif
    }
}

// MARK: - 宽屏判定（环境值，全局共享）

private struct WideLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// iPad 全屏 / iPhone 横屏 / macOS：放大排版并启用多列布局
    var isWideLayout: Bool {
        get { self[WideLayoutKey.self] }
        set { self[WideLayoutKey.self] = newValue }
    }
}

extension View {
    /// 按可用宽度注入 isWideLayout，并给出内容最大宽度
    func wideLayout(_ max: CGFloat = 1400) -> some View {
        GeometryReader { geo in
            self.environment(\.isWideLayout, geo.size.width >= 700)
                .frame(maxWidth: max, alignment: .center)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - 自适应列数

/// 根据容器宽度算列数：`floor((w + spacing) / (minWidth + spacing))`，并夹在上限内。
struct AdaptiveColumns {
    static func count(for width: CGFloat, minimum: CGFloat, spacing: CGFloat, maximum: Int) -> Int {
        guard width > 0 else { return maximum }
        let n = Int(((width + spacing) / (minimum + spacing)).rounded(.down))
        return max(1, min(maximum, n))
    }

    static func grid(for width: CGFloat, minimum: CGFloat, spacing: CGFloat, maximum: Int) -> [GridItem] {
        let n = count(for: width, minimum: minimum, spacing: spacing, maximum: maximum)
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: n)
    }
}

extension Font {
    /// 比分数字等宽，避免刷新时宽度跳动
    static func scoreNumber(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    /// 数据表格数字
    static func statNumber(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
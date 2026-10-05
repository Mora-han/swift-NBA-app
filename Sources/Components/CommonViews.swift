import SwiftUI
import NBAKit

// MARK: - 队徽 + 队名（所有列表复用）

struct TeamBadge: View {
    let logoURL: String?
    let name: String?
    var abbr: String?
    var size: CGFloat = 28

    var body: some View {
        RemoteImage(urlString: logoURL, width: size, height: size)
    }
}

// MARK: - 数据指标网格（球员/球队详情共用）

/// 自适应列数网格，展示「指标名 / 数值 / 联盟排名」。
/// 用 `GridItem.adaptive` 让列数随容器宽度自动增减：宽屏一行放更多格子，
/// 而不是把单元格里的字无限撑大。高度由内容决定，无需手算。
struct StatGrid: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        let value: String
        var rank: Int?
        var accent: Color = .accentColor
    }

    let items: [Item]
    /// 单格最小宽度（约等于「联盟第 12」这类副文案不折行所需的宽度）
    var minimumCellWidth: CGFloat = 92
    var maximumCellWidth: CGFloat = 220

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimumCellWidth, maximum: maximumCellWidth),
                               spacing: 8)],
            spacing: 8
        ) {
            ForEach(items) { item in
                cell(item)
            }
        }
    }

    private func cell(_ item: StatGrid.Item) -> some View {
        VStack(spacing: 3) {
            Text(item.title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(item.value.isEmpty ? "—" : item.value)
                .font(.statNumber(20, weight: .semibold))
                .foregroundStyle(item.value.isEmpty ? .secondary : item.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(item.rank.map { "联盟第 \($0)" } ?? " ")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Theme.tileRadius))
    }
}

// MARK: - 键值信息行

struct InfoRow: View {
    let label: String
    let value: String
    var monospacedValue = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            Text(value.isEmpty ? "—" : value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 15))
        .padding(.vertical, 3)
    }
}

/// 分组小标题（系统 Section header 风格）
struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 胜/负标签

struct WinLossBadge: View {
    let won: Bool
    var body: some View {
        Image(systemName: won ? "arrow.up.right" : "arrow.down.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(won ? Theme.win : Theme.loss)
            .frame(width: 16, height: 16)
            .background((won ? Theme.win : Theme.loss).opacity(0.15), in: .rect(cornerRadius: 4))
    }
}

/// 连胜/连败（虎扑返回 "4" 或 "-4"）
struct StreakBadge: View {
    let streak: String?

    var body: some View {
        if let s = streak, let value = Int(s), value != 0 {
            let winning = value > 0
            Text("\(winning ? "" : "-")\(abs(value))")
                .font(.statNumber(11, weight: .bold))
                .foregroundStyle(.white)
                .frame(minWidth: 22)
                .padding(.vertical, 3)
                .padding(.horizontal, 5)
                .background(winning ? Theme.win : Theme.loss, in: .capsule)
        }
    }
}

// MARK: - 加载 / 空状态

struct LoadingBlock: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
            Text("加载中…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

struct FailureBlock: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        #if os(macOS)
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("加载失败")
                .font(.title3.weight(.medium))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button("重试", action: retry)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        #else
        ContentUnavailableView {
            Label("加载失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message).multilineTextAlignment(.center)
        } actions: {
            if let retry {
                Button("重试", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
        #endif
    }
}

struct EmptyBlock: View {
    let title: String
    var message: String?
    var systemImage: String = "tray"

    var body: some View {
        #if os(macOS)
        // macOS 用更宽松的居中布局，符合桌面应用的留白习惯
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title3.weight(.medium))
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        #else
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        }
        #endif
    }
}

// MARK: - 横向可滚动的指标选择条（榜单 / 球队指标）

struct MetricPicker: View {
    let title: String
    let items: [String]
    @Binding var selection: String
    var systemImage: String = "chart.bar.fill"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        Button {
                            withAnimation(.snappy(duration: 0.22)) { selection = item }
                        } label: {
                            Text(item)
                                .font(.system(size: 15))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(selection == item ? AnyShapeStyle(Color.accentColor)
                                            : AnyShapeStyle(.quaternary),
                                            in: .capsule)
                                .foregroundStyle(selection == item ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// 指标可能重名（如多个维度都有「得分」），因此用稳定 id 选择、展示名只用于文字。
struct IdMetricPicker: View {
    let title: String
    let items: [IdentifiedMetric]
    @Binding var selectionID: String
    var systemImage: String = "chart.bar.fill"

    var body: some View {
        MetricPicker(title: title,
                     items: items.map(\.displayName),
                     selection: Binding(get: {
                         items.first { $0.id == selectionID }?.displayName ?? selectionID
                     }, set: { newValue in
                         if let hit = items.first(where: { $0.displayName == newValue }) {
                             selectionID = hit.id
                         }
                     }),
                     systemImage: systemImage)
    }
}

struct IdentifiedMetric: Identifiable, Hashable {
    let id: String
    let displayName: String
}


// MARK: - 赛季选择

struct SeasonPicker: View {
    let seasons: [String]
    @Binding var selection: String

    var body: some View {
        Picker("赛季", selection: $selection) {
            ForEach(seasons, id: \.self) { Text($0).tag($0) }
        }
        .pickerStyle(.menu)
        .font(.system(size: 15))
    }
}
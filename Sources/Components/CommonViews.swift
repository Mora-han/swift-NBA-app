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

/// 2-4 列自适应网格，展示「指标名 / 数值 / 联盟排名」
struct StatGrid: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        let value: String
        var rank: Int?
        var accent: Color = .accentColor
    }

    let items: [Item]
    var columns: Int = 4

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns),
            spacing: 8
        ) {
            ForEach(items) { item in
                VStack(spacing: 3) {
                    Text(item.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(item.value.isEmpty ? "—" : item.value)
                        .font(.statNumber(17, weight: .semibold))
                        .foregroundStyle(item.value.isEmpty ? .secondary : item.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let rank = item.rank {
                        Text("联盟第 \(rank)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(" ").font(.system(size: 9))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Theme.tileRadius))
            }
        }
    }
}

// MARK: - 键值信息行

struct InfoRow: View {
    let label: String
    let value: String
    var monospacedValue = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value.isEmpty ? "—" : value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }
}

/// 分组小标题（系统 Section header 风格）
struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
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
                .font(.statNumber(10, weight: .bold))
                .foregroundStyle(.white)
                .frame(minWidth: 20)
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(winning ? Theme.win : Theme.loss, in: .capsule)
        }
    }
}

// MARK: - 加载 / 空状态

struct LoadingBlock: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
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
    }
}

struct EmptyBlock: View {
    let title: String
    var message: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "tray")
        } description: {
            if let message { Text(message) }
        }
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
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        Button {
                            withAnimation(.snappy(duration: 0.22)) { selection = item }
                        } label: {
                            Text(item)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    item == selection ? Color.accentColor : Color(.tertiarySystemFill),
                                    in: .capsule
                                )
                                .foregroundStyle(item == selection ? Color.white : Color.primary)
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

// MARK: - 赛季选择

struct SeasonPicker: View {
    let seasons: [String]
    @Binding var selection: String

    var body: some View {
        Picker("赛季", selection: $selection) {
            ForEach(seasons, id: \.self) { Text($0).tag($0) }
        }
        .pickerStyle(.menu)
    }
}
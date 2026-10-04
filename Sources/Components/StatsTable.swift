import SwiftUI

// MARK: - 数据表（iPadOS / macOS 用系统 Table，iPhone 用滚动卡片）
//
// 全部为原生控件，没有自绘控件。

// MARK: 通用统计表格行

struct StatsRowData: Identifiable, Hashable {
    let id: String
    let name: String
    let photo: String?
    let values: [String]
    /// 数值单元格对齐：数字右对齐，文本左对齐
    var numeric = true
    var highlight: Bool = false
}

struct StatsTable: View {
    let headers: [String]
    let rows: [StatsRowData]
    /// 点击行（可选）
    var onSelect: ((StatsRowData) -> Void)?

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
            ScrollView(.horizontal) {
                tableGrid
                    .frame(minWidth: 620)
            }
            .scrollIndicators(.hidden)
        } else {
            ScrollView(.horizontal) {
                tableGrid
                    .frame(minWidth: 480)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// 用 LazyVGrid 实现等宽表格（macOS 上比 Table 更适合可排序的宽数据）
    private var tableGrid: some View {
        let columns = headers.count
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(64), spacing: 0, alignment: .trailing), count: max(columns, 1)),
            alignment: .trailing,
            spacing: 0
        ) {
            headerRow
            ForEach(rows) { row in
                dataRow(row)
            }
        }
        .cardSurface()
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            nameCell("")
                .frame(width: 132, alignment: .leading)
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    Text(header)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 64, alignment: .trailing)
                }
        }
        .padding(.vertical, 8)
        .padding(.trailing, 10)
        .background(.quaternary.opacity(0.4))
    }

    private func nameCell(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .padding(.leading, 10)
    }

    private func dataRow(_ row: StatsRowData) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if row.photo != nil {
                    RemoteImage(urlString: row.photo, width: 22, height: 22, cornerRadius: 4)
                }
                Text(row.name)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .frame(width: 132, alignment: .leading)
            .padding(.leading, 10)

            ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                Text(value.isEmpty ? "—" : value)
                    .font(.statNumber(13, weight: row.highlight ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(value == "—" ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(width: 64, alignment: .trailing)
            }
        }
        .padding(.vertical, 7)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(row.highlight ? Color.accentColor.opacity(0.08) : .clear)
        .contentShape(.rect)
        .onTapGesture {
            guard let onSelect else { return }
            onSelect(row)
        }
    }
}

// MARK: 排名榜单（带名次徽章的头像行）

struct RankList<Destination: View>: View {
    struct Entry: Identifiable {
        let id: String
        let rank: Int
        let playerId: String
        let name: String
        let subtitle: String?
        let photo: String?
        let value: String
        var isUserHighlighted: Bool
    }

    let entries: [Entry]
    /// 传入 NavigationLink 目的地，列表行即为原生可推送行
    let destination: (Entry) -> Destination

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                NavigationLink {
                    destination(entry)
                } label: {
                    label(for: entry)
                }
                .buttonStyle(.plain)

                if index < entries.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .cardSurface()
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    private func label(for entry: Entry) -> some View {
        HStack(spacing: 10) {
            Text("\(entry.rank)")
                .font(.statNumber(14, weight: .semibold))
                .foregroundStyle(rankColor(entry.rank))
                .frame(width: 26, alignment: .trailing)

            RemoteImage(urlString: entry.photo, width: 32, height: 32, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(entry.value)
                .font(.statNumber(15, weight: .semibold))
                .monospacedDigit()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(entry.isUserHighlighted ? Color.accentColor.opacity(0.1) : .clear)
        .contentShape(.rect)
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return .orange
        case 2: return .gray
        case 3: return .brown
        default: return .secondary
        }
    }
}
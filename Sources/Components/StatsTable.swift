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

    var body: some View {
        ScrollView(.horizontal) {
            tableGrid
        }
        .scrollIndicators(.hidden)
    }

    /// 用 LazyVStack 实现等宽表格；每列宽度由表头字数估算，避免中文表头被截断。
    /// 名称列用固定宽度，其余列等宽，横向内容不足时整体可滚动。
    private var tableGrid: some View {
        let widths = resolvedColumnWidths
        return LazyVStack(spacing: 0) {
            headerRow(widths: widths)
            ForEach(rows) { row in
                dataRow(row, widths: widths)
            }
        }
        .frame(minWidth: totalWidth(for: widths))
        .cardSurface()
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    private func totalWidth(for widths: [CGFloat]) -> CGFloat {
        widths.reduce(0, +) + 24
    }

    /// 中文按全宽、其余按半宽估算列宽，并夹在合理区间内
    private var resolvedColumnWidths: [CGFloat] {
        headers.map { header in
            let textWidth = header.reduce(0.0) { acc, ch in
                acc + (isWideGlyph(ch) ? 14.0 : 8.0)
            }
            return max(58, min(130, textWidth + 24))
        }
    }

    private func isWideGlyph(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x2E80...0x9FFF).contains(v) || (0xFF00...0xFFEF).contains(v)
    }

    private func headerRow(widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: nameColumnWidth, height: 0)
            ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                Text(header)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: widths[safe: index] ?? 58, alignment: .trailing)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.quaternary.opacity(0.4))
    }

    private var nameColumnWidth: CGFloat { 150 }

    private func dataRow(_ row: StatsRowData, widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                if row.photo != nil {
                    RemoteImage(urlString: row.photo, width: 28, height: 28, cornerRadius: 6)
                }
                Text(row.name)
                    .font(.system(size: 14))
                    .lineLimit(1)
            }
            .frame(width: nameColumnWidth, alignment: .leading)

            ForEach(Array(row.values.enumerated()), id: \.offset) { index, value in
                Text(value.isEmpty ? "\u{2014}" : value)
                    .font(.statNumber(14, weight: row.highlight ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(value.isEmpty || value == "\u{2014}" ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(width: widths[safe: index] ?? 58, alignment: .trailing)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .frame(minWidth: totalWidth(for: widths), alignment: .leading)
        .background(row.highlight ? Color.accentColor.opacity(0.08) : .clear)
        .contentShape(.rect)
        .onTapGesture {
            guard let onSelect else { return }
            onSelect(row)
        }
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
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
                    Divider().padding(.leading, 58)
                }
            }
        }
        .cardSurface()
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    private func label(for entry: Entry) -> some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.statNumber(16, weight: .semibold))
                .foregroundStyle(rankColor(entry.rank))
                .frame(width: 30, alignment: .trailing)

            RemoteImage(urlString: entry.photo, width: 44, height: 44, cornerRadius: 8, contentMode: .fill)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)
                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 10)

            Text(entry.value)
                .font(.statNumber(19, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
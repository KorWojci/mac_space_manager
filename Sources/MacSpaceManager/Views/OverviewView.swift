import SpaceCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.treeVersion
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                stats
                if let breakdown = model.breakdown {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(title: "Disk at a Glance",
                                          subtitle: "Each square is 1% of \(ByteFormat.string(breakdown.total)). Click a square to see what is inside.")
                            SquarePieChart(breakdown: breakdown, selection: selectedCategory)
                                .frame(maxWidth: 520)
                            CategoryLegend(breakdown: breakdown, selection: selectedCategory)
                        }
                        .card(padding: 20)
                        .frame(minWidth: 420, maxWidth: 560)

                        CategoryDetail(breakdown: breakdown, category: model.selectedCategory ?? .applications)
                            .card(padding: 20)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(20)
        }
    }

    private var selectedCategory: Binding<UsageCategory?> {
        Binding(get: { model.selectedCategory }, set: { model.selectedCategory = $0 })
    }

    private var stats: some View {
        let volume = model.volume
        return HStack(spacing: 14) {
            StatCard(title: "Capacity", value: (volume?.totalCapacity ?? 0).formattedBytes,
                     symbol: "internaldrive.fill", swatch: Palette.blue, caption: volume?.name)
            StatCard(title: "Used", value: (volume?.usedCapacity ?? 0).formattedBytes,
                     symbol: "chart.pie.fill", swatch: Palette.pink,
                     caption: volume.map { ByteFormat.percent($0.usedCapacity, of: $0.totalCapacity) + " full" })
            StatCard(title: "Available", value: (volume?.availableCapacity ?? 0).formattedBytes,
                     symbol: "checkmark.seal.fill", swatch: Palette.green, caption: "Including purgeable space")
            Button {
                model.selection = .cleanup
            } label: {
                StatCard(title: "Safe to Clean", value: model.isScanningCleanup ? "…" : model.reclaimableBytes.formattedBytes,
                         symbol: "sparkles", swatch: Palette.yellow,
                         caption: model.reviewableBytes > 0 ? "+ \(model.reviewableBytes.formattedBytes) to review" : "Open Cleanup")
            }
            .buttonStyle(.plain)
        }
    }
}

/// A 10×10 waffle ("square pie") chart. Each square is 1% of the total.
struct SquarePieChart: View {
    let breakdown: UsageBreakdown
    @Binding var selection: UsageCategory?

    @State private var hovered: UsageCategory?

    private let columns = 10
    private let spacing: CGFloat = 5

    var body: some View {
        let cells = makeCells()
        GeometryReader { geo in
            let side = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            VStack(spacing: spacing) {
                ForEach(0..<columns, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            cell(cells[index], showsIcon: isFirst(index, in: cells), side: side)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.spring(duration: 0.25), value: hovered)
        .animation(.spring(duration: 0.25), value: selection)
    }

    private func cell(_ category: UsageCategory, showsIcon: Bool, side: CGFloat) -> some View {
        let swatch = Palette.swatch(for: category)
        let emphasized = hovered ?? selection
        let dimmed = emphasized != nil && emphasized != category
        let size = breakdown.entry(for: category)?.size ?? 0

        return RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
            .fill(swatch.gradient)
            .overlay {
                if showsIcon && side > 18 {
                    Image(systemName: category.symbol)
                        .font(.system(size: side * 0.42, weight: .semibold))
                        .foregroundStyle(swatch.label)
                }
            }
            .overlay {
                if selection == category {
                    RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.55), lineWidth: 2)
                }
            }
            .frame(width: side, height: side)
            .opacity(dimmed ? 0.3 : 1)
            .scaleEffect(hovered == category ? 1.06 : 1)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { hovered = category } else if hovered == category { hovered = nil }
            }
            .onTapGesture { selection = category }
            .help("\(category.title): \(size.formattedBytes) (\(ByteFormat.percent(size, of: breakdown.total)))")
            .accessibilityElement()
            .accessibilityLabel("\(category.title), \(size.formattedBytes)")
            .accessibilityAddTraits(.isButton)
    }

    private func makeCells() -> [UsageCategory] {
        let entries = breakdown.entries
        let counts = SquarePie.allocate(entries.map(\.size), cells: columns * columns)
        var cells: [UsageCategory] = []
        for (entry, count) in zip(entries, counts) {
            cells.append(contentsOf: Array(repeating: entry.category, count: count))
        }
        while cells.count < columns * columns { cells.append(.free) }
        return Array(cells.prefix(columns * columns))
    }

    private func isFirst(_ index: Int, in cells: [UsageCategory]) -> Bool {
        index == 0 || cells[index - 1] != cells[index]
    }
}

struct CategoryLegend: View {
    let breakdown: UsageBreakdown
    @Binding var selection: UsageCategory?

    var body: some View {
        let entries = breakdown.entries.filter { $0.size > 0 }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 6) {
            ForEach(entries) { entry in
                let swatch = Palette.swatch(for: entry.category)
                Button {
                    selection = entry.category
                } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(swatch.gradient)
                            .frame(width: 14, height: 14)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.category.title)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Text("\(entry.size.formattedBytes) · \(ByteFormat.percent(entry.size, of: breakdown.total))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selection == entry.category ? swatch.color.opacity(0.2) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The biggest space consumers of the selected category.
struct CategoryDetail: View {
    @Environment(AppModel.self) private var model
    let breakdown: UsageBreakdown
    let category: UsageCategory

    var body: some View {
        let entry = breakdown.entry(for: category)
        let swatch = Palette.swatch(for: category)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: category.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(swatch.label)
                    .frame(width: 44, height: 44)
                    .background(swatch.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.title2.weight(.bold))
                    Text("\((entry?.size ?? 0).formattedBytes) · \(ByteFormat.percent(entry?.size ?? 0, of: breakdown.total)) of disk")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let items = entry?.topItems, !items.isEmpty {
                Text("Biggest space consumers")
                    .font(.headline)
                LazyVStack(spacing: 2) {
                    ForEach(items) { node in
                        FileRow(node: node, reference: items.first?.size ?? 1, tint: swatch.color)
                    }
                }
            } else {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyMessage: String {
        switch category {
        case .system:
            return "macOS, system data, other users and folders outside the scanned location. Scan the entire disk to break this down further."
        case .free:
            return "Space available for new files, including purgeable space macOS frees automatically."
        default:
            return "No individual files larger than 1 MB were found in this category."
        }
    }
}

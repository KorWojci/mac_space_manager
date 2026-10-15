import SpaceCore
import SwiftUI

struct ExplorerView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: FileNode?

    var body: some View {
        let _ = model.treeVersion
        if let root = model.root {
            let focus = model.focusNode ?? root
            VStack(alignment: .leading, spacing: 14) {
                Breadcrumbs(focus: focus) { node in
                    model.focusNode = node
                    selected = nil
                }
                HStack(alignment: .top, spacing: 16) {
                    TreemapView(nodes: focus.children, selected: selected) { node in
                        if node.canDrillDown {
                            model.focusNode = node
                            selected = nil
                        } else {
                            selected = node
                        }
                    }
                    .padding(8)
                    .glassSurface()

                    InspectorPanel(focus: focus, selected: $selected)
                        .frame(width: 320)
                }
            }
            .padding(20)
        }
    }
}

private struct Breadcrumbs: View {
    let focus: FileNode
    let onSelect: (FileNode) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if let parent = focus.parent { onSelect(parent) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .disabled(focus.parent == nil)
            .help("Up one level")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(focus.pathFromRoot.enumerated()), id: \.element.id) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.compact.right")
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            onSelect(node)
                        } label: {
                            HStack(spacing: 5) {
                                FileIcon(url: node.url, size: 16)
                                Text(node.name)
                                    .font(.callout.weight(node === focus ? .semibold : .regular))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(node === focus ? Palette.blue.color.opacity(0.18) : .clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
            Text("\(focus.size.formattedBytes) · \(focus.itemCount.formatted()) items")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 14)
    }
}

/// Squarified treemap: every tile's area is proportional to its size on disk.
struct TreemapView: View {
    let nodes: [FileNode]
    let selected: FileNode?
    let onTap: (FileNode) -> Void

    private struct Tile: Identifiable {
        let node: FileNode
        let rect: CGRect
        let swatch: Swatch
        var id: ObjectIdentifier { node.id }
    }

    var body: some View {
        GeometryReader { geo in
            let tiles = layout(in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(tiles) { tile in
                    TreemapTile(node: tile.node, swatch: tile.swatch, isSelected: tile.node === selected)
                        .frame(width: max(0, tile.rect.width - 4), height: max(0, tile.rect.height - 4))
                        .offset(x: tile.rect.minX + 2, y: tile.rect.minY + 2)
                        .onTapGesture { onTap(tile.node) }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .overlay {
            if nodes.isEmpty {
                Text("This folder is empty")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func layout(in bounds: CGRect) -> [Tile] {
        // Cap the tile count so tiles stay large enough to read and click.
        let shown = Array(nodes.prefix(60))
        let rects = SquarifiedTreemap.layout(shown.map { Double($0.size) }, in: bounds)
        var tiles: [Tile] = []
        var colorIndex = 0
        for (node, rect) in zip(shown, rects) where rect.width >= 1 && rect.height >= 1 {
            let swatch: Swatch
            if node.kind == .aggregate {
                swatch = Palette.gray
            } else {
                swatch = Palette.tiles[colorIndex % Palette.tiles.count]
                colorIndex += 1
            }
            tiles.append(Tile(node: node, rect: rect, swatch: swatch))
        }
        return tiles
    }
}

private struct TreemapTile: View {
    let node: FileNode
    let swatch: Swatch
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let shape = RoundedRectangle(cornerRadius: min(10, min(w, h) * 0.18), style: .continuous)

            ZStack(alignment: .topLeading) {
                shape.fill(swatch.gradient)
                if node.canDrillDown && w > 90 && h > 70 {
                    // Hint at the folder's own structure with faint inner tiles.
                    InnerTiles(node: node, color: swatch.label)
                        .padding(EdgeInsets(top: 44, leading: 6, bottom: 6, trailing: 6))
                }
                label(width: w, height: h)
                    .padding(8)
            }
            .overlay {
                shape.strokeBorder(isSelected ? Color.primary : Color.white.opacity(isHovered ? 0.9 : 0),
                                   lineWidth: isSelected ? 3 : 2)
            }
            .brightness(isHovered ? 0.06 : 0)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help("\(node.name)\n\(node.size.formattedBytes)\(node.canDrillDown ? " — click to open" : "")")
        .contextMenu { FileContextMenu(node: node) }
        .accessibilityElement()
        .accessibilityLabel("\(node.name), \(node.size.formattedBytes)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func label(width: CGFloat, height: CGFloat) -> some View {
        if width > 70 && height > 38 {
            let titleSize: CGFloat = min(17, max(11, min(width / 10, height / 4)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if width > 110 {
                        Image(systemName: icon)
                            .font(.system(size: titleSize * 0.85, weight: .semibold))
                    }
                    Text(node.name)
                        .font(.system(size: titleSize, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(node.size.formattedBytes)
                    .font(.system(size: max(10, titleSize - 2), weight: .medium).monospacedDigit())
                    .opacity(0.85)
            }
            .foregroundStyle(swatch.label)
        } else if width > 44 && height > 18 {
            Text(node.size.formattedBytes)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(swatch.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var icon: String {
        switch node.kind {
        case .directory: return "folder.fill"
        case .package: return "app.fill"
        case .aggregate: return "square.stack.3d.up.fill"
        case .file: return "doc.fill"
        }
    }
}

/// Faint preview of a folder's children inside its tile.
private struct InnerTiles: View {
    let node: FileNode
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let shown = Array(node.children.prefix(24))
            let rects = SquarifiedTreemap.layout(shown.map { Double($0.size) },
                                                 in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(rects.enumerated()), id: \.offset) { _, rect in
                    if rect.width > 3 && rect.height > 3 {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(color.opacity(0.22), lineWidth: 1)
                            .frame(width: rect.width - 2, height: rect.height - 2)
                            .offset(x: rect.minX + 1, y: rect.minY + 1)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct InspectorPanel: View {
    @Environment(AppModel.self) private var model
    let focus: FileNode
    @Binding var selected: FileNode?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let node = selected {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            FileIcon(url: node.url, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(node.name)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(node.size.formattedBytes)
                                    .font(.title3.weight(.bold).monospacedDigit())
                            }
                        }
                        Text(node.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if node.isDeletable {
                            HStack {
                                Button("Reveal", systemImage: "magnifyingglass") { model.reveal(node.url) }
                                Spacer()
                                Button(node.url.pathExtension == "app" ? "Uninstall…" : "Delete…", systemImage: "trash") {
                                    model.requestDeletion(of: [node])
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Palette.red.color)
                            }
                        }
                    }
                    .card(padding: 14)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Largest here", subtitle: "Click a tile to open folders or inspect files.")
                    let items = Array(focus.children.prefix(25))
                    ForEach(items) { node in
                        FileRow(node: node, reference: items.first?.size ?? 1, isSelected: node === selected)
                            .onTapGesture {
                                if node.canDrillDown {
                                    model.focusNode = node
                                    selected = nil
                                } else {
                                    selected = node
                                }
                            }
                    }
                }
                .card(padding: 14)
            }
        }
    }
}

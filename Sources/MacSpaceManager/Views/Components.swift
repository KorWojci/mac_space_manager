import AppKit
import SpaceCore
import SwiftUI

/// Finder icon for a file or folder.
struct FileIcon: View {
    let url: URL
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// Standard actions for a scanned item.
struct FileContextMenu: View {
    @Environment(AppModel.self) private var model
    let node: FileNode

    var body: some View {
        if node.kind != .aggregate {
            Button("Reveal in Finder", systemImage: "magnifyingglass") { model.reveal(node.url) }
            Button("Open", systemImage: "arrow.up.forward.app") { model.open(node.url) }
            Divider()
            Button(node.url.pathExtension == "app" ? "Uninstall with Leftovers…" : "Delete…",
                   systemImage: "trash", role: .destructive) {
                model.requestDeletion(of: [node])
            }
        } else {
            Button("Reveal Folder in Finder", systemImage: "magnifyingglass") { model.reveal(node.url) }
        }
    }
}

/// A readable row with icon, name, location, size bar and quick actions.
struct FileRow: View {
    @Environment(AppModel.self) private var model
    let node: FileNode
    /// Size used to scale the bar (typically the biggest sibling).
    let reference: Int64
    var tint: Color = Palette.blue.color
    var isSelected = false

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            FileIcon(url: node.url)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(node.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(node.size.formattedBytes)
                        .font(.body.weight(.semibold).monospacedDigit())
                }
                GeometryReader { geo in
                    let fraction = reference > 0 ? min(1, Double(node.size) / Double(reference)) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(tint).frame(width: max(4, geo.size.width * fraction))
                    }
                }
                .frame(height: 5)
                Text(node.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if node.isDeletable {
                HStack(spacing: 4) {
                    Button { model.reveal(node.url) } label: { Image(systemName: "magnifyingglass") }
                        .help("Reveal in Finder")
                    Button { model.requestDeletion(of: [node]) } label: { Image(systemName: "trash") }
                        .help("Delete")
                }
                .buttonStyle(.borderless)
                .opacity(isHovered || isSelected ? 1 : 0)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? tint.opacity(0.18) : (isHovered ? Color.primary.opacity(0.05) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu { FileContextMenu(node: node) }
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.bold))
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let symbol: String
    let swatch: Swatch
    var caption: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(swatch.label)
                .frame(width: 46, height: 46)
                .background(swatch.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.bold).monospacedDigit())
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 14)
    }
}

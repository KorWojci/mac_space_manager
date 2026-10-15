import SpaceCore
import SwiftUI

struct LargestFilesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<FileNode.ID>()
    @State private var search = ""

    var body: some View {
        let _ = model.treeVersion
        let rows = filteredRows
        let selectedNodes = rows.filter { selection.contains($0.id) }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Largest Files",
                              subtitle: "The \(model.largestFiles.count) biggest files and apps in \(model.scanTarget.title).")
                Spacer()
                if !selectedNodes.isEmpty {
                    Text("\(selectedNodes.count) selected · \(selectedNodes.reduce(Int64(0)) { $0 + $1.size }.formattedBytes)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button("Delete Selected…", systemImage: "trash") {
                    model.requestDeletion(of: selectedNodes)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.red.color)
                .disabled(selectedNodes.isEmpty)
            }

            Table(rows, selection: $selection) {
                TableColumn("Name") { node in
                    HStack(spacing: 8) {
                        FileIcon(url: node.url, size: 20)
                        Text(node.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .width(min: 200, ideal: 320)

                TableColumn("Size") { node in
                    Text(node.size.formattedBytes)
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(sizeColor(node.size))
                }
                .width(min: 80, ideal: 100, max: 140)

                TableColumn("Kind") { node in
                    Text(kind(of: node))
                        .foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 90, max: 140)

                TableColumn("Location") { node in
                    Text(node.url.deletingLastPathComponent().path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .contextMenu(forSelectionType: FileNode.ID.self) { ids in
                let nodes = rows.filter { ids.contains($0.id) }
                if nodes.count == 1, let node = nodes.first {
                    FileContextMenu(node: node)
                } else if !nodes.isEmpty {
                    Button("Delete \(nodes.count) Items…", systemImage: "trash", role: .destructive) {
                        model.requestDeletion(of: nodes)
                    }
                }
            } primaryAction: { ids in
                if let node = rows.first(where: { ids.contains($0.id) }) { model.reveal(node.url) }
            }
            .scrollContentBackground(.hidden)
            .glassSurface(cornerRadius: 14)
        }
        .padding(20)
        .searchable(text: $search, prompt: "Filter by name or path")
    }

    private var filteredRows: [FileNode] {
        guard !search.isEmpty else { return model.largestFiles }
        return model.largestFiles.filter { $0.path.localizedCaseInsensitiveContains(search) }
    }

    private func kind(of node: FileNode) -> String {
        if node.kind == .package { return node.url.pathExtension == "app" ? "Application" : "Bundle" }
        let ext = node.url.pathExtension
        return ext.isEmpty ? "File" : ext.uppercased()
    }

    private func sizeColor(_ size: Int64) -> Color {
        switch size {
        case 10_000_000_000...: return Palette.red.color
        case 1_000_000_000...: return Palette.orange.color
        default: return .primary
        }
    }
}

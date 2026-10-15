import SpaceCore
import SwiftUI

/// Confirms deleting items, including the leftover support files of apps.
struct DeleteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var request: DeletionRequest
    @State private var mode: RemovalMode = .moveToTrash

    init(request: DeletionRequest) {
        _request = State(initialValue: request)
    }

    private var isUninstall: Bool { request.items.contains { $0.url.pathExtension == "app" } }
    private var total: Int64 { request.itemsSize + request.selectedLeftoverSize }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: isUninstall ? "xmark.app.fill" : "trash.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Palette.red.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2.weight(.bold))
                    Text("Frees about \(total.formattedBytes)")
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(request.items) { node in
                            row(url: node.url, name: node.name, size: node.size)
                        }
                    }

                    if !request.leftovers.isEmpty {
                        Divider()
                        HStack {
                            Text("Leftover files")
                                .font(.headline)
                            Text(request.selectedLeftoverSize.formattedBytes)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(allLeftoversSelected ? "Deselect All" : "Select All") {
                                let value = !allLeftoversSelected
                                for index in request.leftovers.indices { request.leftovers[index].isSelected = value }
                            }
                            .buttonStyle(.link)
                        }
                        Text("Preferences, caches, containers and saved state the app keeps in your Library.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        ForEach($request.leftovers) { $candidate in
                            Toggle(isOn: $candidate.isSelected) {
                                row(url: candidate.entry.url,
                                    name: candidate.entry.url.lastPathComponent,
                                    size: candidate.entry.size,
                                    showsParent: true)
                            }
                            .toggleStyle(.checkbox)
                        }
                    } else if isUninstall {
                        Label("No leftover files were found in your Library.", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 320)

            Picker("When deleting:", selection: $mode) {
                ForEach(RemovalMode.allCases) { mode in
                    Text(mode == .moveToTrash ? "Move to Trash (can be restored)" : "Delete immediately (frees space now)")
                        .tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    model.confirmDeletion(request, mode: mode)
                } label: {
                    Text(mode == .moveToTrash ? "Move to Trash" : "Delete \(total.formattedBytes)")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.red.color)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var title: String {
        if isUninstall && request.items.count == 1 { return "Uninstall \(request.items[0].name)?" }
        if request.items.count == 1 { return "Delete \(request.items[0].name)?" }
        return "Delete \(request.items.count) items?"
    }

    private var allLeftoversSelected: Bool { request.leftovers.allSatisfy(\.isSelected) }

    private func row(url: URL, name: String, size: Int64, showsParent: Bool = false) -> some View {
        HStack(spacing: 10) {
            FileIcon(url: url, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if showsParent {
                    Text(url.deletingLastPathComponent().path.replacingOccurrences(of: model.home.path, with: "~"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Text(size.formattedBytes)
                .font(.callout.weight(.semibold).monospacedDigit())
        }
    }
}

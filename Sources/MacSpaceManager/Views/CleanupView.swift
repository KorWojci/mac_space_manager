import SpaceCore
import SwiftUI

struct CleanupView: View {
    @Environment(AppModel.self) private var model
    @State private var confirming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                if model.isScanningCleanup && model.cleanupCategories.isEmpty {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Looking for files that can be removed…")
                            .foregroundStyle(.secondary)
                    }
                    .card()
                }
                group(.safe, title: "Safe to Delete",
                      subtitle: "macOS and your apps recreate these automatically when needed.")
                group(.review, title: "Review Before Deleting",
                      subtitle: "Usually unneeded, but check the contents first.")
            }
            .padding(20)
            .padding(.bottom, 80)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .confirmationDialog(
            "Permanently delete \(model.selectedCleanupBytes.formattedBytes)?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Delete \(model.selectedCleanupBytes.formattedBytes)", role: .destructive) {
                model.performCleanup()
            }
        } message: {
            Text("The selected items are removed immediately and do not go to the Trash.")
        }
    }

    private var summary: some View {
        HStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Palette.yellow.label)
                .frame(width: 64, height: 64)
                .background(Palette.yellow.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(model.isScanningCleanup ? "Calculating…" : "\(model.reclaimableBytes.formattedBytes) can be freed safely")
                    .font(.title.weight(.bold).monospacedDigit())
                Text("Plus \(model.reviewableBytes.formattedBytes) worth reviewing. Select categories below and press Clean Up.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Rescan", systemImage: "arrow.clockwise") { model.scanCleanup() }
                .disabled(model.isScanningCleanup)
        }
        .card(padding: 20)
    }

    @ViewBuilder
    private func group(_ safety: CleanupSafety, title: String, subtitle: String) -> some View {
        let categories = model.cleanupCategories.filter { $0.safety == safety }
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title, subtitle: subtitle)
                ForEach(categories) { category in
                    CleanupCard(category: category)
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.selectedCleanupBytes.formattedBytes)
                    .font(.title2.weight(.bold).monospacedDigit())
            }
            Spacer()
            Button {
                confirming = true
            } label: {
                Label("Clean Up", systemImage: "sparkles")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.green.color)
            .controlSize(.large)
            .disabled(model.selectedCleanupBytes == 0 || model.isRemoving || model.isScanningCleanup)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassSurface(cornerRadius: 20)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

private struct CleanupCard: View {
    @Environment(AppModel.self) private var model
    let category: CleanupCategory
    @State private var expanded = false

    var body: some View {
        let isOn = Binding(
            get: { model.selectedCleanupIDs.contains(category.id) },
            set: { on in
                if on { model.selectedCleanupIDs.insert(category.id) } else { model.selectedCleanupIDs.remove(category.id) }
            }
        )
        let tint = Palette.color(for: category.safety)
        let isEmpty = category.totalSize == 0

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Toggle("", isOn: isOn)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(isEmpty)
                Image(systemName: category.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(category.title)
                            .font(.headline)
                        Text(category.safety == .safe ? "Safe" : "Review")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .foregroundStyle(Color.black.opacity(0.8))
                            .background(tint.opacity(0.85), in: Capsule())
                    }
                    Text(category.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(isEmpty ? "Clean" : category.totalSize.formattedBytes)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(isEmpty ? Color.secondary : Color.primary)
                    if !isEmpty {
                        Text("\(category.entries.count) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .font(.body.weight(.semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(isEmpty)
                .help(expanded ? "Hide items" : "Show items")
            }

            if expanded {
                Divider()
                VStack(spacing: 2) {
                    ForEach(category.entries.prefix(40)) { entry in
                        HStack(spacing: 10) {
                            FileIcon(url: entry.url, size: 20)
                            Text(entry.url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(entry.size.formattedBytes)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Button {
                                model.reveal(entry.url)
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .buttonStyle(.borderless)
                            .help("Reveal in Finder")
                        }
                        .padding(.vertical, 3)
                    }
                    if category.entries.count > 40 {
                        Text("and \(category.entries.count - 40) more…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, 34)
            }
        }
        .card(padding: 14)
        .opacity(isEmpty ? 0.65 : 1)
    }
}

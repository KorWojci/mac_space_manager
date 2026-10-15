import SpaceCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            VStack(spacing: 0) {
                if !model.hasFullDiskAccess {
                    FullDiskAccessBanner()
                }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(BackdropGradient())
            .toolbar { scanToolbar }
            .navigationTitle(model.selection?.title ?? "Space Manager")
            .navigationSubtitle(model.scanTarget.title)
        }
        .sheet(item: $model.deletionRequest) { request in
            DeleteSheet(request: request)
        }
        .overlay(alignment: .bottom) { ToastView() }
        .task {
            if model.root == nil && !model.isScanning {
                model.scan()
                model.scanCleanup()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if model.root == nil {
            if model.isScanning {
                ScanningView()
            } else {
                EmptyStateView()
            }
        } else {
            switch model.selection ?? .overview {
            case .overview: OverviewView()
            case .explorer: ExplorerView()
            case .largest: LargestFilesView()
            case .cleanup: CleanupView()
            }
        }
    }
}

/// Soft, bright wash behind the glass cards.
struct BackdropGradient: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let opacity = colorScheme == .dark ? 0.18 : 0.12
        LinearGradient(
            colors: [
                Palette.blue.color.opacity(opacity),
                Palette.purple.color.opacity(opacity * 0.8),
                Palette.mint.color.opacity(opacity),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selection) {
            Section("Storage") {
                ForEach(SidebarItem.allCases) { item in
                    Label {
                        HStack {
                            Text(item.title)
                            Spacer()
                            if item == .cleanup && model.reclaimableBytes > 0 {
                                Text(model.reclaimableBytes.formattedBytes)
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Palette.green.color.opacity(0.22), in: Capsule())
                            }
                        }
                    } icon: {
                        Image(systemName: item.symbol)
                    }
                    .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if let volume = model.volume {
                VolumeGauge(volume: volume)
                    .padding(12)
            }
        }
    }
}

private struct VolumeGauge: View {
    let volume: VolumeInfo

    var body: some View {
        let fraction = volume.totalCapacity > 0 ? Double(volume.usedCapacity) / Double(volume.totalCapacity) : 0
        VStack(alignment: .leading, spacing: 6) {
            Label(volume.name, systemImage: "internaldrive.fill")
                .font(.callout.weight(.semibold))
            ProgressView(value: fraction)
                .tint(fraction > 0.9 ? Palette.red.color : Palette.blue.color)
            Text("\(volume.availableCapacity.formattedBytes) free of \(volume.totalCapacity.formattedBytes)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card(padding: 12)
    }
}

extension ContentView {
    @ToolbarContentBuilder
    var scanToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.isScanning || model.isRemoving {
                ProgressView()
                    .controlSize(.small)
                    .help(model.isRemoving ? "Removing files…" : "Scanning \(model.progress.currentPath)")
            }

            Menu {
                Button("Home Folder", systemImage: "house") { model.scan(.home) }
                Button("Entire Disk", systemImage: "internaldrive") { model.scan(.disk) }
                Divider()
                Button("Choose Folder…", systemImage: "folder") { model.chooseFolder() }
            } label: {
                Label("Scan Target", systemImage: "scope")
            }
            .help("Choose what to scan")

            if model.isScanning {
                Button("Stop", systemImage: "stop.fill") { model.cancelScan() }
                    .help("Stop scanning")
            } else {
                Button("Rescan", systemImage: "arrow.clockwise") {
                    model.scan()
                    model.scanCleanup()
                }
                .help("Scan \(model.scanTarget.title) again")
            }
        }
    }
}

private struct FullDiskAccessBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(Palette.orange.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("Grant Full Disk Access for complete results")
                    .font(.headline)
                Text("Some folders such as Mail, Safari and app containers can only be measured with Full Disk Access.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open System Settings") { model.openFullDiskAccessSettings() }
                .buttonStyle(.borderedProminent)
                .tint(Palette.orange.color)
        }
        .card(padding: 14)
        .padding([.horizontal, .top], 20)
    }
}

private struct ScanningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning \(model.scanTarget.title)…")
                .font(.title2.weight(.semibold))
            HStack(spacing: 24) {
                StatPill(title: "Items", value: model.progress.itemsScanned.formatted())
                StatPill(title: "Measured", value: model.progress.bytesScanned.formattedBytes)
            }
            Text(model.progress.currentPath)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)
            Button("Stop") { model.cancelScan() }
                .controlSize(.large)
        }
        .card(padding: 32)
        .padding(40)
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 110)
    }
}

private struct EmptyStateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 54))
                .foregroundStyle(Palette.blue.color, Palette.pink.color)
            Text("See what fills your disk")
                .font(.title.weight(.bold))
            Text("Scan a location to get a square chart of everything that takes up space.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Scan Home Folder") { model.scan(.home) }
                    .buttonStyle(.borderedProminent)
                Button("Scan Entire Disk") { model.scan(.disk) }
                Button("Choose Folder…") { model.chooseFolder() }
            }
            .controlSize(.large)
        }
        .card(padding: 36)
        .padding(40)
    }
}

private struct ToastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let toast = model.toast {
            HStack(spacing: 10) {
                Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(toast.isError ? Palette.orange.color : Palette.green.color)
                    .font(.title3)
                Text(toast.message)
                    .font(.callout.weight(.medium))
                    .lineLimit(3)
                Button {
                    model.toast = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassSurface(cornerRadius: 22)
            .frame(maxWidth: 640)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(toast.isError ? 10 : 5))
                if model.toast?.id == toast.id { model.toast = nil }
            }
        }
    }
}

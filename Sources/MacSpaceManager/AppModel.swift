import AppKit
import Observation
import SpaceCore
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case overview, explorer, largest, cleanup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .explorer: return "Explorer"
        case .largest: return "Largest Files"
        case .cleanup: return "Cleanup"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.3x3.fill"
        case .explorer: return "rectangle.split.3x3.fill"
        case .largest: return "list.number"
        case .cleanup: return "sparkles"
        }
    }
}

enum ScanTarget: Hashable {
    case home
    case disk
    case folder(URL)

    var url: URL {
        switch self {
        case .home: return FileManager.default.homeDirectoryForCurrentUser
        case .disk: return URL(fileURLWithPath: "/")
        case .folder(let url): return url
        }
    }

    var title: String {
        switch self {
        case .home: return "Home Folder"
        case .disk: return "Entire Disk"
        case .folder(let url): return url.lastPathComponent
        }
    }
}

struct LeftoverCandidate: Identifiable {
    let entry: CleanupEntry
    var isSelected = true
    var id: URL { entry.url }
}

struct DeletionRequest: Identifiable {
    let id = UUID()
    let items: [FileNode]
    var leftovers: [LeftoverCandidate]

    var itemsSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedLeftoverSize: Int64 { leftovers.filter(\.isSelected).reduce(0) { $0 + $1.entry.size } }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let isError: Bool
}

@MainActor
@Observable
final class AppModel {
    let home = FileManager.default.homeDirectoryForCurrentUser

    var selection: SidebarItem? = .overview
    private(set) var scanTarget: ScanTarget = .home

    // Scan state
    private(set) var root: FileNode?
    private(set) var isScanning = false
    private(set) var progress = ScanProgress()
    private(set) var volume: VolumeInfo?
    private(set) var breakdown: UsageBreakdown?
    private(set) var largestFiles: [FileNode] = []
    /// Bumped whenever the (non-observable) file tree is mutated.
    private(set) var treeVersion = 0
    var focusNode: FileNode?
    var selectedCategory: UsageCategory? = .applications

    // Cleanup state
    private(set) var cleanupCategories: [CleanupCategory] = []
    private(set) var isScanningCleanup = false
    var selectedCleanupIDs: Set<String> = []

    // Deletion
    var deletionRequest: DeletionRequest?
    private(set) var isRemoving = false
    var toast: Toast?

    private(set) var hasFullDiskAccess = true

    @ObservationIgnored private var scanner: DiskScanner?

    init() {
        hasFullDiskAccess = Self.checkFullDiskAccess(home: home)
    }

    // MARK: Scanning

    func scan(_ target: ScanTarget? = nil) {
        if let target { scanTarget = target }
        scanner?.cancel()

        let scanner = DiskScanner()
        self.scanner = scanner
        let url = scanTarget.url
        isScanning = true
        progress = ScanProgress(currentPath: url.path)
        volume = VolumeInfo.forURL(url)
        hasFullDiskAccess = Self.checkFullDiskAccess(home: home)

        let report: @Sendable (ScanProgress) -> Void = { snapshot in
            Task { @MainActor in
                if self.scanner === scanner { self.progress = snapshot }
            }
        }
        Task {
            let node = await Task.detached(priority: .userInitiated) {
                scanner.scan(url, progress: report)
            }.value
            guard self.scanner === scanner, !scanner.isCancelled else { return }
            self.root = node
            self.focusNode = node
            self.isScanning = false
            self.recomputeDerivedData()
        }
    }

    func cancelScan() {
        scanner?.cancel()
        scanner = nil
        isScanning = false
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder or disk to analyze."
        if panel.runModal() == .OK, let url = panel.url {
            scan(.folder(url))
        }
    }

    private func recomputeDerivedData() {
        guard let root else { return }
        breakdown = UsageBreakdown.compute(root: root, classifier: UsageClassifier(homeDirectory: home), volume: volume)
        largestFiles = root.largestItems(limit: 500)
        treeVersion += 1
    }

    // MARK: Cleanup

    var reclaimableBytes: Int64 {
        cleanupCategories.filter { $0.safety == .safe }.reduce(0) { $0 + $1.totalSize }
    }

    var reviewableBytes: Int64 {
        cleanupCategories.filter { $0.safety == .review }.reduce(0) { $0 + $1.totalSize }
    }

    var selectedCleanupBytes: Int64 {
        cleanupCategories.filter { selectedCleanupIDs.contains($0.id) }.reduce(0) { $0 + $1.totalSize }
    }

    func scanCleanup() {
        guard !isScanningCleanup else { return }
        isScanningCleanup = true
        let home = self.home
        Task {
            let categories = await Task.detached(priority: .utility) {
                CleanupScanner(homeDirectory: home).scan()
            }.value
            self.cleanupCategories = categories
            self.selectedCleanupIDs = Set(categories.filter { $0.safety == .safe && $0.totalSize > 0 }.map(\.id))
            self.isScanningCleanup = false
        }
    }

    func performCleanup() {
        let entries = cleanupCategories.filter { selectedCleanupIDs.contains($0.id) }.flatMap(\.entries)
        guard !entries.isEmpty else { return }
        remove(entries, mode: .deletePermanently) { [weak self] in self?.scanCleanup() }
    }

    // MARK: Deletion

    func requestDeletion(of nodes: [FileNode]) {
        let items = nodes.filter(\.isDeletable)
        guard !items.isEmpty else { return }
        let finder = LeftoverFinder(homeDirectory: home)
        var leftovers: [CleanupEntry] = []
        for item in items {
            if let app = AppBundleReader.read(item.url) {
                leftovers.append(contentsOf: finder.leftovers(for: app))
            }
        }
        let selectedPaths = Set(items.map(\.path))
        let candidates = leftovers
            .filter { !selectedPaths.contains($0.url.path) }
            .map { LeftoverCandidate(entry: $0) }
        deletionRequest = DeletionRequest(items: items, leftovers: candidates)
    }

    func confirmDeletion(_ request: DeletionRequest, mode: RemovalMode) {
        deletionRequest = nil
        let entries = request.items.map { CleanupEntry(url: $0.url, size: $0.size) }
            + request.leftovers.filter(\.isSelected).map(\.entry)
        remove(entries, mode: mode) { [weak self] in
            if !request.leftovers.isEmpty { self?.scanCleanup() }
        }
    }

    private func remove(_ entries: [CleanupEntry], mode: RemovalMode, completion: @escaping () -> Void) {
        isRemoving = true
        let home = self.home
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                FileRemover.remove(entries, mode: mode, home: home)
            }.value
            self.isRemoving = false
            self.apply(report)
            completion()
        }
    }

    private func apply(_ report: RemovalReport) {
        if let root {
            for url in report.removed {
                guard let node = root.node(at: url), node !== root else { continue }
                if focusNode.map({ $0.path == node.path || $0.path.hasPrefix(node.path + "/") }) == true {
                    focusNode = node.parent
                }
                node.removeFromParent()
            }
        }
        volume = VolumeInfo.forURL(scanTarget.url)
        recomputeDerivedData()

        let verb = report.mode == .moveToTrash ? "Moved to Trash" : "Freed"
        if report.failures.isEmpty {
            toast = Toast(message: "\(verb) \(report.bytes.formattedBytes)", isError: false)
        } else {
            let first = report.failures[0]
            toast = Toast(
                message: "\(verb) \(report.bytes.formattedBytes). \(report.failures.count) item(s) could not be removed: "
                    + "\(first.url.lastPathComponent) — \(first.message)",
                isError: true
            )
        }
    }

    // MARK: Finder helpers

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func checkFullDiskAccess(home: URL) -> Bool {
        // Safari's folder is only readable with Full Disk Access.
        let probe = home.appendingPathComponent("Library/Safari")
        guard FileManager.default.fileExists(atPath: probe.path) else { return true }
        return (try? FileManager.default.contentsOfDirectory(atPath: probe.path)) != nil
    }
}

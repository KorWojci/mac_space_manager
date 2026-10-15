import Foundation

public enum CleanupSafety: String, Sendable {
    /// Regenerated automatically by macOS or the app that created it.
    case safe
    /// Usually removable, but worth a look before deleting.
    case review
}

public struct CleanupEntry: Identifiable, Hashable, Sendable {
    public let url: URL
    public let size: Int64
    public var id: URL { url }

    public init(url: URL, size: Int64) {
        self.url = url
        self.size = size
    }
}

public struct CleanupCategory: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    /// SF Symbol name.
    public let symbol: String
    public let safety: CleanupSafety
    public let entries: [CleanupEntry]

    public var totalSize: Int64 { entries.reduce(0) { $0 + $1.size } }
}

/// Finds well-known locations whose contents can be removed to reclaim space.
public struct CleanupScanner: Sendable {
    public let home: URL
    public let applicationFolders: [URL]

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationFolders: [URL]? = nil
    ) {
        home = homeDirectory.standardizedFileURL
        self.applicationFolders = applicationFolders ?? [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            homeDirectory.appendingPathComponent("Applications"),
        ]
    }

    private enum Source {
        /// Every item inside these folders (the folders themselves stay).
        case contents([String])
        /// Top-level files in a folder with one of these extensions.
        case files(in: String, extensions: Set<String>)
        /// Support files of apps that are no longer installed.
        case orphans
    }

    private struct Rule {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let safety: CleanupSafety
        let source: Source
    }

    private var rules: [Rule] {
        [
            Rule(id: "user-caches", title: "App Caches",
                 detail: "Temporary data apps keep to load faster. Apps rebuild it when needed.",
                 symbol: "archivebox.fill", safety: .safe, source: .contents(["Library/Caches"])),
            Rule(id: "logs", title: "Logs & Crash Reports",
                 detail: "Diagnostic logs and crash reports written by apps and macOS.",
                 symbol: "doc.plaintext.fill", safety: .safe, source: .contents(["Library/Logs"])),
            Rule(id: "trash", title: "Trash",
                 detail: "Items you already moved to the Trash. Emptying frees the space for good.",
                 symbol: "trash.fill", safety: .safe, source: .contents([".Trash"])),
            Rule(id: "xcode-derived", title: "Xcode Derived Data",
                 detail: "Build products and indexes. Xcode recreates them on the next build.",
                 symbol: "hammer.fill", safety: .safe,
                 source: .contents(["Library/Developer/Xcode/DerivedData"])),
            Rule(id: "device-support", title: "Device Support Files",
                 detail: "Debug symbols for iPhone, Watch, TV and Vision devices. Re-downloaded when a device connects.",
                 symbol: "iphone.gen3", safety: .safe,
                 source: .contents([
                    "Library/Developer/Xcode/iOS DeviceSupport",
                    "Library/Developer/Xcode/watchOS DeviceSupport",
                    "Library/Developer/Xcode/tvOS DeviceSupport",
                    "Library/Developer/Xcode/visionOS DeviceSupport",
                 ])),
            Rule(id: "simulator-caches", title: "Simulator Caches",
                 detail: "Cached data for iOS Simulator runtimes.",
                 symbol: "ipad.and.iphone", safety: .safe,
                 source: .contents(["Library/Developer/CoreSimulator/Caches"])),
            Rule(id: "package-caches", title: "Package Manager Caches",
                 detail: "Downloaded packages from npm, Gradle, Cargo, pip and others. Fetched again on demand.",
                 symbol: "shippingbox.fill", safety: .safe,
                 source: .contents([".npm/_cacache", ".gradle/caches", ".cargo/registry/cache", ".cache"])),
            Rule(id: "mail-downloads", title: "Mail Attachments",
                 detail: "Copies of attachments you opened in Mail. The originals stay in your mailbox.",
                 symbol: "paperclip", safety: .safe,
                 source: .contents(["Library/Containers/com.apple.mail/Data/Library/Mail Downloads"])),
            Rule(id: "installers", title: "Installers in Downloads",
                 detail: "Disk images and installer packages. Usually not needed once the app is installed.",
                 symbol: "opticaldisc.fill", safety: .review,
                 source: .files(in: "Downloads", extensions: ["dmg", "pkg", "mpkg", "xip", "iso"])),
            Rule(id: "xcode-archives", title: "Xcode Archives",
                 detail: "Archived app builds. Keep the ones you may need to symbolicate crash reports.",
                 symbol: "archivebox", safety: .review,
                 source: .contents(["Library/Developer/Xcode/Archives"])),
            Rule(id: "device-backups", title: "iPhone & iPad Backups",
                 detail: "Local device backups. Make sure you have a recent backup in iCloud before removing.",
                 symbol: "externaldrive.fill", safety: .review,
                 source: .contents(["Library/Application Support/MobileSync/Backup"])),
            Rule(id: "app-leftovers", title: "Leftovers of Removed Apps",
                 detail: "Support files, containers and saved state of apps that are no longer installed.",
                 symbol: "puzzlepiece.extension.fill", safety: .review, source: .orphans),
        ]
    }

    /// Scans all cleanup locations. Slow on big folders; call off the main thread.
    public func scan() -> [CleanupCategory] {
        rules.map { rule in
            let urls: [URL]
            switch rule.source {
            case .contents(let paths):
                urls = paths.flatMap { children(of: home.appendingPathComponent($0)) }
            case .files(let folder, let extensions):
                urls = children(of: home.appendingPathComponent(folder)).filter {
                    extensions.contains($0.pathExtension.lowercased())
                }
            case .orphans:
                let installed = AppBundleReader.installedBundleIdentifiers(in: applicationFolders)
                urls = LeftoverFinder(homeDirectory: home).orphanedItems(installedBundleIdentifiers: installed)
            }
            let entries = urls
                .map { CleanupEntry(url: $0, size: DiskScanner.allocatedSize(of: $0)) }
                .filter { $0.size > 0 }
                .sorted { $0.size > $1.size }
            return CleanupCategory(id: rule.id, title: rule.title, detail: rule.detail,
                                   symbol: rule.symbol, safety: rule.safety, entries: entries)
        }
    }

    private func children(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [])) ?? []
    }
}

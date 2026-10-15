import Foundation

public struct AppBundleInfo: Sendable, Equatable {
    public let url: URL
    public let name: String
    public let bundleIdentifier: String?
}

public enum AppBundleReader {
    public static func read(_ appURL: URL) -> AppBundleInfo? {
        guard appURL.pathExtension.lowercased() == "app" else { return nil }
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        var identifier: String?
        var name = appURL.deletingPathExtension().lastPathComponent
        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            identifier = plist["CFBundleIdentifier"] as? String
            if let bundleName = plist["CFBundleName"] as? String, !bundleName.isEmpty {
                name = bundleName
            }
        }
        return AppBundleInfo(url: appURL, name: name, bundleIdentifier: identifier)
    }

    /// Bundle identifiers of apps in `folders` and one level of subfolders.
    public static func installedBundleIdentifiers(in folders: [URL]) -> Set<String> {
        let fm = FileManager.default
        var result: Set<String> = []
        func visit(_ folder: URL, depth: Int) {
            guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: []) else { return }
            for item in items {
                if item.pathExtension.lowercased() == "app" {
                    if let id = read(item)?.bundleIdentifier { result.insert(id.lowercased()) }
                } else if depth < 1 {
                    visit(item, depth: depth + 1)
                }
            }
        }
        folders.forEach { visit($0, depth: 0) }
        return result
    }
}

/// Finds the support files an app leaves behind in `~/Library`.
public struct LeftoverFinder: Sendable {
    public let library: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        library = homeDirectory.standardizedFileURL.appendingPathComponent("Library")
    }

    private struct Location {
        let path: String
        /// Whether folders named after the app (not just its bundle id) count.
        let matchesName: Bool
    }

    private static let locations: [Location] = [
        Location(path: "Application Support", matchesName: true),
        Location(path: "Caches", matchesName: true),
        Location(path: "Logs", matchesName: true),
        Location(path: "Preferences", matchesName: false),
        Location(path: "Preferences/ByHost", matchesName: false),
        Location(path: "Containers", matchesName: false),
        Location(path: "Group Containers", matchesName: false),
        Location(path: "Saved Application State", matchesName: false),
        Location(path: "HTTPStorages", matchesName: false),
        Location(path: "WebKit", matchesName: false),
        Location(path: "Cookies", matchesName: false),
        Location(path: "LaunchAgents", matchesName: false),
        Location(path: "Application Scripts", matchesName: false),
    ]

    /// Leftover files belonging to `app`, biggest first.
    public func leftovers(for app: AppBundleInfo) -> [CleanupEntry] {
        let bundleID = app.bundleIdentifier?.lowercased()
        let appName = app.name.lowercased()
        let fm = FileManager.default
        var found: [URL] = []

        for location in Self.locations {
            let folder = library.appendingPathComponent(location.path)
            guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: []) else { continue }
            for item in items {
                let name = item.lastPathComponent.lowercased()
                var matches = false
                if let bundleID {
                    matches = name == bundleID
                        || name.hasPrefix(bundleID + ".")
                        || name.hasSuffix("." + bundleID)
                }
                if !matches && location.matchesName && appName.count >= 3 {
                    matches = name == appName
                }
                if matches { found.append(item) }
            }
        }
        return found
            .map { CleanupEntry(url: $0, size: DiskScanner.allocatedSize(of: $0)) }
            .sorted { $0.size > $1.size }
    }

    private static let orphanLocations = [
        "Application Support", "Containers", "Saved Application State", "HTTPStorages", "WebKit",
    ]

    /// Items named after bundle identifiers of apps that are not installed.
    public func orphanedItems(installedBundleIdentifiers installed: Set<String>) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for location in Self.orphanLocations {
            let folder = library.appendingPathComponent(location)
            guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: []) else { continue }
            for item in items where Self.isOrphan(name: item.lastPathComponent, installed: installed) {
                result.append(item)
            }
        }
        return result
    }

    static func isOrphan(name: String, installed: Set<String>) -> Bool {
        var id = name.lowercased()
        for suffix in [".savedstate", ".plist", ".binarycookies"] where id.hasSuffix(suffix) {
            id.removeLast(suffix.count)
        }
        guard looksLikeBundleIdentifier(id), !id.hasPrefix("com.apple.") else { return false }
        for app in installed {
            if id == app || id.hasPrefix(app + ".") || app.hasPrefix(id + ".") { return false }
        }
        return true
    }

    static func looksLikeBundleIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

import Foundation

public enum RemovalMode: String, CaseIterable, Identifiable, Sendable {
    case moveToTrash
    case deletePermanently

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .moveToTrash: return "Move to Trash"
        case .deletePermanently: return "Delete Immediately"
        }
    }
}

public struct RemovalFailure: Sendable {
    public let url: URL
    public let message: String
}

public struct RemovalReport: Sendable {
    public var removed: [URL] = []
    public var bytes: Int64 = 0
    public var failures: [RemovalFailure] = []
    public var mode: RemovalMode
}

/// Refuses to touch folders whose removal would break macOS or the user account.
public enum SafetyGuard {
    private static let protectedSystemPaths: Set<String> = [
        "/", "/Applications", "/Library", "/System", "/Users", "/Volumes", "/bin", "/sbin", "/usr", "/opt",
        "/private", "/private/var", "/private/etc", "/private/tmp", "/etc", "/var", "/tmp", "/cores", "/dev",
    ]
    private static let protectedHomePaths: [String] = [
        "", "Library", "Library/Application Support", "Library/Caches", "Library/Containers",
        "Library/Group Containers", "Library/Preferences", "Library/Logs", "Library/Developer",
        "Library/Mail", "Library/Messages", "Library/Mobile Documents", "Applications", "Desktop",
        "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", ".Trash",
    ]

    public static func isProtected(_ url: URL, home: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if protectedSystemPaths.contains(path) { return true }
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/") || path.hasPrefix("/bin/") || path.hasPrefix("/sbin/") {
            return true
        }
        let homePath = home.standardizedFileURL.path
        return protectedHomePaths.contains { relative in
            path == (relative.isEmpty ? homePath : homePath + "/" + relative)
        }
    }
}

public enum FileRemover {
    /// Removes the given items. Items nested inside another item in the list are skipped
    /// (their parent removal covers them). Items already in the Trash are always deleted
    /// permanently.
    public static func remove(
        _ entries: [CleanupEntry],
        mode: RemovalMode,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> RemovalReport {
        var report = RemovalReport(mode: mode)
        let fm = FileManager.default
        let trashPath = home.standardizedFileURL.appendingPathComponent(".Trash").path + "/"

        let unique = Dictionary(entries.map { ($0.url.standardizedFileURL.path, $0) }, uniquingKeysWith: { a, _ in a })
        let paths = unique.keys.sorted()
        var removedParents: [String] = []

        for path in paths {
            guard let entry = unique[path] else { continue }
            if removedParents.contains(where: { path.hasPrefix($0 + "/") }) { continue }
            let url = URL(fileURLWithPath: path)
            if SafetyGuard.isProtected(url, home: home) {
                report.failures.append(RemovalFailure(url: url, message: "Protected location, left untouched."))
                continue
            }
            do {
                if mode == .moveToTrash && !path.hasPrefix(trashPath) {
                    #if os(macOS)
                    try fm.trashItem(at: url, resultingItemURL: nil)
                    #else
                    try fm.removeItem(at: url)
                    #endif
                } else {
                    try fm.removeItem(at: url)
                }
                report.removed.append(url)
                report.bytes += entry.size
                removedParents.append(path)
            } catch {
                report.failures.append(RemovalFailure(url: url, message: error.localizedDescription))
            }
        }
        return report
    }
}

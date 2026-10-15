import Foundation

/// High level buckets shown in the square pie chart.
public enum UsageCategory: String, CaseIterable, Identifiable, Sendable {
    case applications
    case documents
    case media
    case developer
    case cachesAndLogs
    case mailAndMessages
    case trash
    case other
    case system
    case free

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .applications: return "Applications"
        case .documents: return "Documents"
        case .media: return "Photos & Media"
        case .developer: return "Developer"
        case .cachesAndLogs: return "Caches & Logs"
        case .mailAndMessages: return "Mail & Messages"
        case .trash: return "Trash"
        case .other: return "Other Files"
        case .system: return "System & Not Scanned"
        case .free: return "Free Space"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .applications: return "app.badge"
        case .documents: return "doc.text"
        case .media: return "photo.on.rectangle"
        case .developer: return "hammer"
        case .cachesAndLogs: return "archivebox"
        case .mailAndMessages: return "envelope"
        case .trash: return "trash"
        case .other: return "folder"
        case .system: return "gearshape"
        case .free: return "circle.dashed"
        }
    }

    /// Categories that come from scanned files (rather than volume totals).
    public var isScanned: Bool { self != .system && self != .free }
}

/// Maps paths and file names to a `UsageCategory`.
public struct UsageClassifier: Sendable {
    private let rules: [(prefix: String, category: UsageCategory)]
    private let homePath: String

    public init(homeDirectory: URL) {
        let home = homeDirectory.standardizedFileURL.path
        homePath = home
        func h(_ relative: String) -> String { home + "/" + relative }
        let raw: [(String, UsageCategory)] = [
            ("/Applications", .applications),
            (h("Applications"), .applications),

            (h("Library/Developer"), .developer),
            ("/Library/Developer", .developer),
            (h("Library/Android"), .developer),
            (h("Library/Containers/com.docker.docker"), .developer),
            (h(".npm"), .developer), (h(".gradle"), .developer), (h(".m2"), .developer),
            (h(".cargo"), .developer), (h(".rustup"), .developer), (h("go"), .developer),
            (h(".cocoapods"), .developer), (h(".docker"), .developer), (h(".pyenv"), .developer),
            (h(".nvm"), .developer), (h("Developer"), .developer),
            ("/opt/homebrew", .developer), ("/usr/local", .developer),

            (h("Library/Caches"), .cachesAndLogs), (h("Library/Logs"), .cachesAndLogs),
            (h(".cache"), .cachesAndLogs),
            ("/Library/Caches", .cachesAndLogs), ("/Library/Logs", .cachesAndLogs),
            ("/private/var/log", .cachesAndLogs),

            (h("Library/Mail"), .mailAndMessages), (h("Library/Messages"), .mailAndMessages),
            (h("Library/Containers/com.apple.mail"), .mailAndMessages),

            (h(".Trash"), .trash),

            (h("Pictures"), .media), (h("Music"), .media), (h("Movies"), .media),

            (h("Documents"), .documents), (h("Desktop"), .documents), (h("Downloads"), .documents),
            (h("Library/Mobile Documents"), .documents),

            ("/System", .system), ("/Library", .system), ("/private", .system),
            ("/usr", .system), ("/bin", .system), ("/sbin", .system), ("/cores", .system),
        ]
        // Longest prefix wins, so e.g. /Library/Caches beats /Library.
        rules = raw.sorted { $0.0.count > $1.0.count }.map { (prefix: $0.0, category: $0.1) }
    }

    /// Category for a whole folder subtree, or nil if it depends on the contents.
    public func category(forPath path: String) -> UsageCategory? {
        // Inside the home folder only home rules apply, wherever the home folder lives.
        let insideHome = path == homePath || path.hasPrefix(homePath + "/")
        for rule in rules where path == rule.prefix || path.hasPrefix(rule.prefix + "/") {
            if insideHome && !rule.prefix.hasPrefix(homePath + "/") { continue }
            return rule.category
        }
        return nil
    }

    static let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "raw", "cr2", "cr3", "nef", "arw", "dng", "psd",
        "mov", "mp4", "m4v", "mkv", "avi", "webm", "mp3", "m4a", "aac", "wav", "flac", "aif", "aiff",
        "photoslibrary", "musiclibrary", "fcpbundle", "imovielibrary", "logicx",
    ]
    static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "rtf", "md", "csv", "epub",
    ]

    /// Category for an individual file or bundle that matched no path rule.
    public func category(forItemNamed name: String) -> UsageCategory {
        let ext = (name as NSString).pathExtension.lowercased()
        if ext == "app" { return .applications }
        if Self.mediaExtensions.contains(ext) { return .media }
        if Self.documentExtensions.contains(ext) { return .documents }
        return .other
    }
}

/// Disk usage split into `UsageCategory` buckets, with the biggest items of each.
public struct UsageBreakdown: Sendable {
    public struct Entry: Identifiable, Sendable {
        public let category: UsageCategory
        public let size: Int64
        /// Largest files and bundles in this category, biggest first.
        public let topItems: [FileNode]
        public var id: UsageCategory { category }
    }

    /// Entries in `UsageCategory.allCases` order (zero-sized ones included).
    public let entries: [Entry]
    /// The total the chart represents: volume capacity, or the scanned size without volume info.
    public let total: Int64

    public func entry(for category: UsageCategory) -> Entry? {
        entries.first { $0.category == category }
    }

    public static func compute(
        root: FileNode,
        classifier: UsageClassifier,
        volume: VolumeInfo?,
        topItemLimit: Int = 30
    ) -> UsageBreakdown {
        var sizes: [UsageCategory: Int64] = [:]
        var items: [UsageCategory: [FileNode]] = [:]

        var stack: [(FileNode, UsageCategory?)] = [(root, nil)]
        while let item = stack.popLast() {
            let (node, inherited) = item
            let ruled = inherited ?? (node.kind == .aggregate ? nil : classifier.category(forPath: node.path))
            switch node.kind {
            case .directory where !node.children.isEmpty:
                for child in node.children { stack.append((child, ruled)) }
            case .directory, .aggregate:
                sizes[ruled ?? .other, default: 0] += node.size
            case .file, .package:
                let category = ruled ?? classifier.category(forItemNamed: node.name)
                sizes[category, default: 0] += node.size
                items[category, default: []].append(node)
            }
        }

        var total = root.size
        if let volume, volume.totalCapacity > 0 {
            total = volume.totalCapacity
            let scanned = sizes.values.reduce(0, +)
            sizes[.system, default: 0] += max(0, volume.usedCapacity - scanned)
            sizes[.free] = volume.availableCapacity
        }

        let entries = UsageCategory.allCases.map { category in
            Entry(
                category: category,
                size: sizes[category] ?? 0,
                topItems: Array((items[category] ?? []).sorted { $0.size > $1.size }.prefix(topItemLimit))
            )
        }
        return UsageBreakdown(entries: entries, total: total)
    }
}

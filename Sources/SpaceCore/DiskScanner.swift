import Foundation

public struct ScanProgress: Sendable, Equatable {
    public var itemsScanned: Int
    public var bytesScanned: Int64
    public var currentPath: String

    public init(itemsScanned: Int = 0, bytesScanned: Int64 = 0, currentPath: String = "") {
        self.itemsScanned = itemsScanned
        self.bytesScanned = bytesScanned
        self.currentPath = currentPath
    }
}

/// Walks a folder and builds a size-annotated `FileNode` tree.
///
/// `scan` is synchronous and should be called off the main thread. Top-level
/// subfolders are scanned in parallel.
public final class DiskScanner: @unchecked Sendable {
    public struct Options: Sendable {
        /// Files smaller than this are folded into an aggregate node.
        public var minimumFileSize: Int64
        /// Folders smaller than this keep their total size but drop their children.
        public var minimumExpandedFolderSize: Int64
        /// Absolute paths that are never entered.
        public var excludedPaths: Set<String>

        public init(
            minimumFileSize: Int64 = 1_000_000,
            minimumExpandedFolderSize: Int64 = 5_000_000,
            excludedPaths: Set<String> = DiskScanner.defaultExcludedPaths
        ) {
            self.minimumFileSize = minimumFileSize
            self.minimumExpandedFolderSize = minimumExpandedFolderSize
            self.excludedPaths = excludedPaths
        }
    }

    /// Mount points and firmlink mirrors that would double count or leave the disk.
    public static let defaultExcludedPaths: Set<String> = [
        "/System/Volumes", "/Volumes", "/dev", "/net", "/home", "/proc", "/sys",
    ]

    static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
    ]
    static let resourceKeySet = Set(resourceKeys)

    private let options: Options
    private let lock = NSLock()
    private var cancelled = false
    private var progress = ScanProgress()
    private var lastReport = Date.distantPast
    private var progressHandler: (@Sendable (ScanProgress) -> Void)?

    public init(options: Options = Options()) {
        self.options = options
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public func scan(_ root: URL, progress handler: (@Sendable (ScanProgress) -> Void)? = nil) -> FileNode {
        lock.lock()
        cancelled = false
        progress = ScanProgress()
        lastReport = .distantPast
        progressHandler = handler
        lock.unlock()

        let node = scanFolder(root.standardizedFileURL.resolvingSymlinksInPath(), kind: .directory, isRoot: true, parallel: true)
        report(path: root.path, force: true)
        return node
    }

    private func scanFolder(_ url: URL, kind: FileNode.Kind, isRoot: Bool, parallel: Bool) -> FileNode {
        report(path: url.path, force: false)
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: Self.resourceKeys, options: [])) ?? []

        var nodes: [FileNode] = []
        var subfolders: [(URL, FileNode.Kind)] = []
        var smallSize: Int64 = 0
        var smallCount = 0

        for child in contents {
            if isCancelled { break }
            if options.excludedPaths.contains(child.path) { continue }
            guard let values = try? child.resourceValues(forKeys: Self.resourceKeySet) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true {
                subfolders.append((child, values.isPackage == true ? .package : .directory))
                continue
            }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            count(bytes: size)
            if size >= options.minimumFileSize {
                nodes.append(FileNode(url: child, kind: .file, size: size))
            } else {
                smallSize += size
                smallCount += 1
            }
        }

        if parallel && subfolders.count > 1 {
            let box = ResultBox(count: subfolders.count)
            DispatchQueue.concurrentPerform(iterations: subfolders.count) { index in
                let (childURL, childKind) = subfolders[index]
                let node = self.scanFolder(childURL, kind: childKind, isRoot: false, parallel: false)
                box.set(node, at: index)
            }
            nodes.append(contentsOf: box.nodes.compactMap { $0 })
        } else {
            for (childURL, childKind) in subfolders where !isCancelled {
                nodes.append(scanFolder(childURL, kind: childKind, isRoot: false, parallel: false))
            }
        }

        let total = nodes.reduce(smallSize) { $0 + $1.size }
        let items = nodes.reduce(smallCount) { $0 + $1.itemCount }
        let keepChildren = kind == .directory && (isRoot || total >= options.minimumExpandedFolderSize)

        if keepChildren && smallCount > 0 && smallSize > 0 {
            let label = smallCount == 1 ? "1 small file" : "\(smallCount) small files"
            nodes.append(FileNode(url: url, name: label, kind: .aggregate, size: smallSize, itemCount: smallCount))
        }
        nodes.sort { $0.size > $1.size }
        return FileNode(url: url, kind: kind, size: total, itemCount: items, children: keepChildren ? nodes : [])
    }

    private func count(bytes: Int64) {
        lock.lock()
        progress.itemsScanned += 1
        progress.bytesScanned += bytes
        lock.unlock()
    }

    private func report(path: String, force: Bool) {
        lock.lock()
        let now = Date()
        guard force || now.timeIntervalSince(lastReport) > 0.15, let handler = progressHandler else {
            lock.unlock()
            return
        }
        lastReport = now
        progress.currentPath = path
        let snapshot = progress
        lock.unlock()
        handler(snapshot)
    }

    /// Total allocated size of a file or folder (used for cleanup estimates).
    public static func allocatedSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: resourceKeySet) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: resourceKeys, options: [], errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let v = try? child.resourceValues(forKeys: resourceKeySet),
                  v.isDirectory != true, v.isSymbolicLink != true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)
        }
        return total
    }
}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var nodes: [FileNode?]

    init(count: Int) { nodes = Array(repeating: nil, count: count) }

    func set(_ node: FileNode, at index: Int) {
        lock.lock()
        nodes[index] = node
        lock.unlock()
    }
}

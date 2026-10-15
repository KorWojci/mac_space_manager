import Foundation

/// A node in the scanned file tree.
///
/// To keep memory bounded on large disks, the scanner only creates nodes for files
/// above a size threshold; the rest of a folder's small files are folded into a
/// single `.aggregate` node.
public final class FileNode: Identifiable, Hashable, @unchecked Sendable {
    public enum Kind: Sendable {
        case file
        case directory
        /// A bundle such as an `.app`, treated as a single item.
        case package
        /// Stand-in for many small files that were not tracked individually.
        case aggregate
    }

    public let url: URL
    public let name: String
    public let kind: Kind
    public internal(set) var size: Int64
    public internal(set) var itemCount: Int
    public internal(set) var children: [FileNode]
    public internal(set) weak var parent: FileNode?

    public var id: ObjectIdentifier { ObjectIdentifier(self) }

    public init(url: URL, name: String? = nil, kind: Kind, size: Int64 = 0, itemCount: Int = 1, children: [FileNode] = []) {
        self.url = url
        self.name = name ?? (url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
        self.kind = kind
        self.size = size
        self.itemCount = itemCount
        self.children = children
        for child in children { child.parent = self }
    }

    public static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    public var path: String { url.path }

    /// True when the node is a folder whose contents can be explored.
    public var canDrillDown: Bool { kind == .directory && !children.isEmpty }

    /// Aggregates are not real files and cannot be deleted directly.
    public var isDeletable: Bool { kind != .aggregate }

    /// Ancestors starting at the tree root and ending with `self`.
    public var pathFromRoot: [FileNode] {
        var result: [FileNode] = [self]
        var current = parent
        while let node = current {
            result.append(node)
            current = node.parent
        }
        return result.reversed()
    }

    func setChildren(_ nodes: [FileNode]) {
        children = nodes
        for child in nodes { child.parent = self }
    }

    /// Detaches the node from its parent and subtracts its size from every ancestor.
    public func removeFromParent() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        var current: FileNode? = parent
        while let node = current {
            node.size = max(0, node.size - size)
            node.itemCount = max(0, node.itemCount - itemCount)
            current = node.parent
        }
        self.parent = nil
    }

    /// Finds the node for `url` in this subtree, if it was tracked.
    public func node(at url: URL) -> FileNode? {
        let target = url.standardizedFileURL.path
        var current: FileNode = self
        if target == current.path { return current }
        while true {
            guard let next = current.children.first(where: {
                $0.kind != .aggregate && (target == $0.path || target.hasPrefix($0.path + "/"))
            }) else { return nil }
            if next.path == target { return next }
            current = next
        }
    }

    /// The largest individual files and bundles in this subtree, biggest first.
    public func largestItems(limit: Int) -> [FileNode] {
        var items: [FileNode] = []
        var stack: [FileNode] = [self]
        while let node = stack.popLast() {
            switch node.kind {
            case .file, .package:
                items.append(node)
            case .directory:
                stack.append(contentsOf: node.children)
            case .aggregate:
                break
            }
        }
        items.sort { $0.size > $1.size }
        return Array(items.prefix(limit))
    }
}

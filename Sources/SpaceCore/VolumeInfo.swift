import Foundation

public struct VolumeInfo: Sendable, Equatable {
    public let name: String
    public let totalCapacity: Int64
    public let availableCapacity: Int64

    public var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }

    public init(name: String, totalCapacity: Int64, availableCapacity: Int64) {
        self.name = name
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
    }

    /// Reads capacity information for the volume containing `url`.
    public static func forURL(_ url: URL) -> VolumeInfo? {
        var keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        #if os(macOS)
        keys.insert(.volumeAvailableCapacityForImportantUsageKey)
        #endif
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }
        var available = Int64(values.volumeAvailableCapacity ?? 0)
        #if os(macOS)
        // Includes purgeable space macOS will free on demand, matching "About This Mac".
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
            available = important
        }
        #endif
        return VolumeInfo(name: values.volumeName ?? "Disk", totalCapacity: Int64(total), availableCapacity: available)
    }
}

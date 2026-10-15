import Foundation

public enum ByteFormat {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    /// Human readable size using decimal units, matching Finder.
    public static func string(_ bytes: Int64) -> String {
        var value = Double(max(bytes, 0))
        var unit = 0
        while value >= 1000 && unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        if unit == 0 { return "\(Int(value)) B" }
        let format = value >= 100 ? "%.0f" : (value >= 10 ? "%.1f" : "%.2f")
        return String(format: format, value) + " " + units[unit]
    }

    public static func percent(_ part: Int64, of total: Int64) -> String {
        guard total > 0 else { return "0%" }
        let value = Double(part) / Double(total) * 100
        if value > 0 && value < 1 { return "<1%" }
        return String(format: "%.0f%%", value)
    }
}

import Foundation

/// Squarified treemap layout (Bruls, Huizing & van Wijk).
///
/// Produces rectangles with aspect ratios close to 1 so every tile stays readable
/// and easy to click.
public enum SquarifiedTreemap {
    /// Returns one rectangle per value, in the same order as `values`.
    /// Non-positive values get `.zero`.
    public static func layout(_ values: [Double], in bounds: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: values.count)
        let order = values.indices.filter { values[$0] > 0 }.sorted { values[$0] > values[$1] }
        guard !order.isEmpty, bounds.width > 0, bounds.height > 0 else { return result }

        let total = order.reduce(0.0) { $0 + values[$1] }
        let scale = Double(bounds.width * bounds.height) / total
        let areas = order.map { values[$0] * scale }

        var remaining = bounds
        var start = 0
        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            while end < areas.count,
                  worstRatio(areas[start...end], side: side) <= worstRatio(areas[start..<end], side: side) {
                end += 1
            }

            let row = areas[start..<end]
            let rowArea = row.reduce(0, +)
            let isLastRow = end == areas.count

            if remaining.width >= remaining.height {
                // Lay the row out as a column on the left edge.
                let height = Double(remaining.height)
                let width = isLastRow ? Double(remaining.width) : rowArea / height
                var y = Double(remaining.minY)
                for (offset, area) in row.enumerated() {
                    let isLast = offset == row.count - 1
                    let h = isLast ? Double(remaining.maxY) - y : area / width
                    result[order[start + offset]] = CGRect(x: Double(remaining.minX), y: y, width: width, height: h)
                    y += h
                }
                remaining = CGRect(x: Double(remaining.minX) + width, y: Double(remaining.minY),
                                   width: max(0, Double(remaining.width) - width), height: height)
            } else {
                // Lay the row out along the top edge.
                let width = Double(remaining.width)
                let height = isLastRow ? Double(remaining.height) : rowArea / width
                var x = Double(remaining.minX)
                for (offset, area) in row.enumerated() {
                    let isLast = offset == row.count - 1
                    let w = isLast ? Double(remaining.maxX) - x : area / height
                    result[order[start + offset]] = CGRect(x: x, y: Double(remaining.minY), width: w, height: height)
                    x += w
                }
                remaining = CGRect(x: Double(remaining.minX), y: Double(remaining.minY) + height,
                                   width: width, height: max(0, Double(remaining.height) - height))
            }
            start = end
        }
        return result
    }

    static func worstRatio(_ row: ArraySlice<Double>, side: Double) -> Double {
        let sum = row.reduce(0, +)
        guard sum > 0, side > 0, let largest = row.max(), let smallest = row.min(), smallest > 0 else {
            return .infinity
        }
        let side2 = side * side
        let sum2 = sum * sum
        return max(side2 * largest / sum2, sum2 / (side2 * smallest))
    }
}

/// Allocates the cells of a "square pie" (waffle) chart.
public enum SquarePie {
    /// Splits `cells` cells proportionally across `sizes` using the largest
    /// remainder method. Every non-zero size receives at least one cell when
    /// there are enough cells to go around.
    public static func allocate(_ sizes: [Int64], cells: Int = 100) -> [Int] {
        let total = sizes.reduce(0) { $0 + max(0, $1) }
        guard total > 0, cells > 0 else { return Array(repeating: 0, count: sizes.count) }

        let exact = sizes.map { Double(max(0, $0)) / Double(total) * Double(cells) }
        var counts = exact.map { Int($0.rounded(.down)) }
        var leftover = cells - counts.reduce(0, +)
        let byRemainder = exact.indices.sorted { (exact[$0] - Double(counts[$0])) > (exact[$1] - Double(counts[$1])) }
        for index in byRemainder where leftover > 0 {
            counts[index] += 1
            leftover -= 1
        }

        // Give tiny categories a visible square by borrowing from the largest one.
        let nonZero = sizes.filter { $0 > 0 }.count
        if nonZero <= cells {
            for index in sizes.indices where sizes[index] > 0 && counts[index] == 0 {
                guard let donor = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[donor] > 1 else { break }
                counts[donor] -= 1
                counts[index] = 1
            }
        }
        return counts
    }
}

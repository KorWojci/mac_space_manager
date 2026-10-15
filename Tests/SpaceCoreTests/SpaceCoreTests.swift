import Foundation
import XCTest
@testable import SpaceCore

final class TreemapTests: XCTestCase {
    func testAreasAreProportionalAndInsideBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
        let values: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let rects = SquarifiedTreemap.layout(values, in: bounds)
        XCTAssertEqual(rects.count, values.count)

        let total = values.reduce(0, +)
        for (value, rect) in zip(values, rects) {
            let expected = value / total * Double(bounds.width * bounds.height)
            XCTAssertEqual(Double(rect.width * rect.height), expected, accuracy: expected * 0.001 + 0.01)
            XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect))
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 0.01, "tiles \(i) and \(j) overlap")
            }
        }
    }

    func testZeroValuesGetEmptyRects() {
        let rects = SquarifiedTreemap.layout([0, 5, -1], in: CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertEqual(rects[0], .zero)
        XCTAssertEqual(rects[2], .zero)
        XCTAssertEqual(Double(rects[1].width * rects[1].height), 100, accuracy: 0.001)
    }

    func testTilesStayReasonablySquare() {
        let rects = SquarifiedTreemap.layout(Array(repeating: 1, count: 16), in: CGRect(x: 0, y: 0, width: 400, height: 400))
        for rect in rects {
            let ratio = max(rect.width / rect.height, rect.height / rect.width)
            XCTAssertLessThan(ratio, 2.5)
        }
    }
}

final class SquarePieTests: XCTestCase {
    func testAllocatesExactlyAllCells() {
        let counts = SquarePie.allocate([333, 333, 334], cells: 100)
        XCTAssertEqual(counts.reduce(0, +), 100)
        XCTAssertEqual(counts, [33, 33, 34])
    }

    func testTinyCategoriesStillVisible() {
        let counts = SquarePie.allocate([1_000_000, 1, 0], cells: 100)
        XCTAssertEqual(counts, [99, 1, 0])
    }

    func testEmptyInput() {
        XCTAssertEqual(SquarePie.allocate([0, 0], cells: 100), [0, 0])
    }
}

final class ByteFormatTests: XCTestCase {
    func testFormatting() {
        XCTAssertEqual(ByteFormat.string(0), "0 B")
        XCTAssertEqual(ByteFormat.string(999), "999 B")
        XCTAssertEqual(ByteFormat.string(1_500), "1.50 KB")
        XCTAssertEqual(ByteFormat.string(25_300_000), "25.3 MB")
        XCTAssertEqual(ByteFormat.string(512_000_000_000), "512 GB")
        XCTAssertEqual(ByteFormat.percent(1, of: 1000), "<1%")
        XCTAssertEqual(ByteFormat.percent(250, of: 1000), "25%")
    }
}

final class FileSystemTests: XCTestCase {
    var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        // /var is a symlink to /private/var on macOS; use the real path like the scanner does.
        home = home.resolvingSymlinksInPath()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    @discardableResult
    func write(_ relative: String, bytes: Int) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: bytes).write(to: url)
        return url
    }

    func testScannerBuildsTreeWithAggregates() throws {
        try write("Movies/big.mov", bytes: 3_000_000)
        try write("Documents/report.pdf", bytes: 2_000_000)
        for i in 0..<5 { try write("Documents/notes-\(i).txt", bytes: 2_000) }
        try write("tiny/a.txt", bytes: 10)

        let scanner = DiskScanner(options: .init(minimumFileSize: 1_000_000, minimumExpandedFolderSize: 1_000_000))
        let root = scanner.scan(home)

        XCTAssertGreaterThanOrEqual(root.size, 5_010_000)
        XCTAssertEqual(root.children.first?.name, "Movies")
        let documents = try XCTUnwrap(root.children.first { $0.name == "Documents" })
        XCTAssertTrue(documents.children.contains { $0.name == "report.pdf" })
        let aggregate = try XCTUnwrap(documents.children.first { $0.kind == .aggregate })
        XCTAssertEqual(aggregate.itemCount, 5)

        // Small folders keep their size but not their children.
        let tiny = try XCTUnwrap(root.children.first { $0.name == "tiny" })
        XCTAssertTrue(tiny.children.isEmpty)

        let largest = root.largestItems(limit: 1)
        XCTAssertEqual(largest.first?.name, "big.mov")
    }

    func testRemovingNodeUpdatesAncestors() throws {
        try write("A/B/file.bin", bytes: 2_000_000)
        try write("A/other.bin", bytes: 2_000_000)
        let root = DiskScanner(options: .init(minimumFileSize: 1, minimumExpandedFolderSize: 1)).scan(home)
        let before = root.size
        let file = try XCTUnwrap(root.node(at: home.appendingPathComponent("A/B/file.bin")))
        let size = file.size
        file.removeFromParent()
        XCTAssertEqual(root.size, before - size)
        XCTAssertNil(root.node(at: home.appendingPathComponent("A/B/file.bin")))
    }

    func testBreakdownClassifiesByLocationAndExtension() throws {
        try write("Movies/clip.mov", bytes: 2_000_000)
        try write("Library/Caches/com.example/cache.db", bytes: 3_000_000)
        try write("Projects/photo.jpg", bytes: 1_500_000)
        try write("Projects/data.bin", bytes: 1_200_000)

        let root = DiskScanner(options: .init(minimumFileSize: 1, minimumExpandedFolderSize: 1)).scan(home)
        let breakdown = UsageBreakdown.compute(root: root, classifier: UsageClassifier(homeDirectory: home), volume: nil)
        XCTAssertGreaterThanOrEqual(breakdown.entry(for: .media)!.size, 3_500_000)
        XCTAssertGreaterThanOrEqual(breakdown.entry(for: .cachesAndLogs)!.size, 3_000_000)
        XCTAssertGreaterThanOrEqual(breakdown.entry(for: .other)!.size, 1_200_000)
        XCTAssertEqual(breakdown.entry(for: .media)!.topItems.first?.name, "clip.mov")

        let volume = VolumeInfo(name: "Test", totalCapacity: 100_000_000, availableCapacity: 40_000_000)
        let withVolume = UsageBreakdown.compute(root: root, classifier: UsageClassifier(homeDirectory: home), volume: volume)
        XCTAssertEqual(withVolume.total, 100_000_000)
        XCTAssertEqual(withVolume.entry(for: .free)!.size, 40_000_000)
        XCTAssertEqual(withVolume.entries.filter { $0.category != .free }.reduce(0) { $0 + $1.size }, 60_000_000)
    }

    func testCleanupScannerFindsCachesAndInstallers() throws {
        try write("Library/Caches/com.example.app/blob", bytes: 50_000)
        try write("Downloads/Setup.dmg", bytes: 40_000)
        try write("Downloads/keep.pdf", bytes: 40_000)

        let categories = CleanupScanner(homeDirectory: home, applicationFolders: []).scan()
        let caches = try XCTUnwrap(categories.first { $0.id == "user-caches" })
        XCTAssertEqual(caches.entries.map(\.url.lastPathComponent), ["com.example.app"])
        XCTAssertEqual(caches.safety, .safe)
        let installers = try XCTUnwrap(categories.first { $0.id == "installers" })
        XCTAssertEqual(installers.entries.map(\.url.lastPathComponent), ["Setup.dmg"])
    }

    func testLeftoversForApp() throws {
        try write("Library/Application Support/com.acme.Rocket/data", bytes: 1_000)
        try write("Library/Application Support/Rocket/config", bytes: 1_000)
        try write("Library/Preferences/com.acme.Rocket.plist", bytes: 100)
        try write("Library/Group Containers/ABCDE12345.com.acme.Rocket/x", bytes: 100)
        try write("Library/Saved Application State/com.acme.Rocket.savedState/w", bytes: 100)
        try write("Library/Preferences/com.acme.RocketLauncherPro.plist", bytes: 100)
        try write("Library/Caches/com.other.App/c", bytes: 100)

        let app = AppBundleInfo(url: home.appendingPathComponent("Rocket.app"), name: "Rocket", bundleIdentifier: "com.acme.Rocket")
        let found = Set(LeftoverFinder(homeDirectory: home).leftovers(for: app).map(\.url.lastPathComponent))
        XCTAssertEqual(found, [
            "com.acme.Rocket", "Rocket", "com.acme.Rocket.plist",
            "ABCDE12345.com.acme.Rocket", "com.acme.Rocket.savedState",
        ])
    }

    func testOrphanDetection() {
        let installed: Set<String> = ["com.acme.rocket", "org.mozilla.firefox"]
        XCTAssertTrue(LeftoverFinder.isOrphan(name: "com.gone.App", installed: installed))
        XCTAssertTrue(LeftoverFinder.isOrphan(name: "com.gone.App.savedState", installed: installed))
        XCTAssertFalse(LeftoverFinder.isOrphan(name: "com.acme.Rocket", installed: installed))
        XCTAssertFalse(LeftoverFinder.isOrphan(name: "com.acme.Rocket.helper", installed: installed))
        XCTAssertFalse(LeftoverFinder.isOrphan(name: "com.apple.Safari", installed: installed))
        XCTAssertFalse(LeftoverFinder.isOrphan(name: "Google", installed: installed))
        XCTAssertFalse(LeftoverFinder.isOrphan(name: "Some Folder.v2.x", installed: installed))
    }

    func testRemoverSkipsProtectedAndNestedItems() throws {
        let folder = try write("Junk/inner/file.bin", bytes: 1_000).deletingLastPathComponent().deletingLastPathComponent()
        let nested = folder.appendingPathComponent("inner/file.bin")
        let documents = home.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)

        let report = FileRemover.remove(
            [CleanupEntry(url: folder, size: 1_000), CleanupEntry(url: nested, size: 1_000), CleanupEntry(url: documents, size: 0)],
            mode: .deletePermanently,
            home: home
        )
        XCTAssertEqual(report.removed.map(\.lastPathComponent), ["Junk"])
        XCTAssertEqual(report.bytes, 1_000)
        XCTAssertEqual(report.failures.map(\.url.lastPathComponent), ["Documents"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: documents.path))
        XCTAssertTrue(SafetyGuard.isProtected(URL(fileURLWithPath: "/System/Library"), home: home))
        XCTAssertTrue(SafetyGuard.isProtected(home, home: home))
    }
}

import XCTest

/// PRIVACY.md: "Takes doesn't read anything in the background." Keys typed in other apps are never watched.
final class BackgroundKeysTests: XCTestCase {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Takes")

    func testNothingWatchesKeysTypedInOtherApps() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 20)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for watcher in ["addGlobalMonitorForEvents", "CGEvent.tapCreate", "CGEventTapCreate"] {
                XCTAssertFalse(source.contains(watcher), "\(file.lastPathComponent) uses \(watcher)")
            }
        }
    }
}

import XCTest
@testable import Takes

/// Move to Applications used to fail without a word: a folder it couldn't make was ignored, and the copy failing to
/// open said nothing. Every failure is now thrown, so setup and onboarding can show it.
final class MoveToApplicationsTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("takes-move-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A minimal app bundle with `identifier`.
    private func app(at url: URL, identifier: String, version: String = "1.0") throws -> URL {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return url
    }

    // MARK: Move to Applications

    func testTakesIsCopiedOverAnOlderTakes() throws {
        let source = try app(at: folder.appendingPathComponent("dmg/Takes.app"), identifier: "com.baramir.takes")
        let applications = folder.appendingPathComponent("Applications", isDirectory: true)
        _ = try app(at: applications.appendingPathComponent("Takes.app"), identifier: "com.baramir.takes")
        let placed = try AppLocation.copyToApplications(from: source, applications: applications)
        let copied = applications.appendingPathComponent("Takes.app")
        XCTAssertEqual(placed, .copied(copied))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.appendingPathComponent("Contents/Info.plist").path))
        let left = try FileManager.default.contentsOfDirectory(atPath: applications.path)
        XCTAssertEqual(left, ["Takes.app"], "No temporary copy is left behind")
    }

    func testANewerTakesIsLeftAsItIsAndOpened() throws {
        let source = try app(at: folder.appendingPathComponent("dmg/Takes.app"), identifier: "com.baramir.takes", version: "1.2")
        let applications = folder.appendingPathComponent("Applications", isDirectory: true)
        let installed = try app(at: applications.appendingPathComponent("Takes.app"), identifier: "com.baramir.takes", version: "1.10")
        guard case .newerThere(let opened) = try AppLocation.copyToApplications(from: source, applications: applications) else {
            return XCTFail("A newer Takes is opened, not replaced")
        }
        XCTAssertEqual(opened.standardizedFileURL.path, installed.standardizedFileURL.path)
        let plist = NSDictionary(contentsOf: installed.appendingPathComponent("Contents/Info.plist"))
        XCTAssertEqual(plist?["CFBundleShortVersionString"] as? String, "1.10", "Not replaced by the older one")
    }

    func testAFailedCopyLeavesTheOldTakesInPlace() throws {
        let source = folder.appendingPathComponent("dmg/Takes.app")
        let applications = folder.appendingPathComponent("Applications", isDirectory: true)
        let installed = try app(at: applications.appendingPathComponent("Takes.app"), identifier: "com.baramir.takes")
        _ = try app(at: source, identifier: "com.baramir.takes", version: "1.1")
        // A part of the new copy can't be read, so copying it fails part-way.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.appendingPathComponent("Contents").path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.appendingPathComponent("Contents").path) }
        XCTAssertThrowsError(try AppLocation.copyToApplications(from: source, applications: applications))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.appendingPathComponent("Contents/Info.plist").path),
                      "Applications still has a Takes")
        let left = try FileManager.default.contentsOfDirectory(atPath: applications.path)
        XCTAssertEqual(left, ["Takes.app"], "The half-made copy is removed")
    }

    func testVersionsCompareNumerically() throws {
        let older = try app(at: folder.appendingPathComponent("a/Takes.app"), identifier: "x", version: "0.9.5")
        let newer = try app(at: folder.appendingPathComponent("b/Takes.app"), identifier: "x", version: "0.10.0")
        XCTAssertTrue(AppLocation.isNewer(newer, than: older))
        XCTAssertFalse(AppLocation.isNewer(older, than: newer))
        XCTAssertFalse(AppLocation.isNewer(older, than: older))
    }

    func testSomethingElseWithTheSameNameIsNeverReplaced() throws {
        let source = try app(at: folder.appendingPathComponent("dmg/Takes.app"), identifier: "com.baramir.takes")
        let applications = folder.appendingPathComponent("Applications", isDirectory: true)
        _ = try app(at: applications.appendingPathComponent("Takes.app"), identifier: "com.example.other")
        XCTAssertThrowsError(try AppLocation.copyToApplications(from: source, applications: applications)) { error in
            guard case AppLocation.MoveError.copyFailed = error else { return XCTFail("\(error)") }
            XCTAssertTrue(error.localizedDescription.hasPrefix("Couldn't copy Takes to Applications"))
        }
    }

    func testAlreadyInApplicationsIsSaid() throws {
        let applications = folder.appendingPathComponent("Applications", isDirectory: true)
        let source = try app(at: applications.appendingPathComponent("Takes.app"), identifier: "com.baramir.takes")
        XCTAssertThrowsError(try AppLocation.copyToApplications(from: source, applications: applications)) { error in
            XCTAssertEqual(error.localizedDescription, "Takes is already in Applications.")
        }
    }

    func testAFolderThatCantBeMadeIsReportedNotIgnored() throws {
        let source = try app(at: folder.appendingPathComponent("dmg/Takes.app"), identifier: "com.baramir.takes")
        let blocker = folder.appendingPathComponent("Applications")
        try Data("not a folder".utf8).write(to: blocker)
        XCTAssertThrowsError(try AppLocation.copyToApplications(from: source, applications: blocker)) { error in
            guard case AppLocation.MoveError.copyFailed = error else { return XCTFail("\(error)") }
        }
    }

    func testOpeningTheCopyHasItsOwnMessage() {
        XCTAssertEqual(AppLocation.MoveError.couldNotOpen.localizedDescription,
                       "Takes was copied to Applications but couldn't be opened from there. Open it from Applications yourself.")
    }
}

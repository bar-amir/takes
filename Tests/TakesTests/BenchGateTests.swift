import Security
import XCTest
@testable import Takes

/// `--bench` spends the user's accounts, so it must refuse in a distributed (Developer ID signed) build.
/// None of these start an engine: a refused run returns before anything else is called.
final class BenchGateTests: XCTestCase {
    private let team = kSecCodeInfoTeamIdentifier as String

    func testADeveloperIDBuildIsRefused() {
        // What SecCodeCopySigningInformation returns for a Developer ID app: the team identifier is among the keys.
        let signed: [String: Any] = ["identifier": "com.baramir.takes", "flags": 0x10000, team: "ABCDE12345"]
        XCTAssertFalse(Bench.isAllowed(signingInformation: signed))
    }

    func testTheAdHocBuildFromBuildShIsAllowed() {
        // `codesign --sign -` leaves no team identifier; the flags carry the ad-hoc bit (0x2).
        let adHoc: [String: Any] = ["identifier": "com.baramir.takes", "flags": 0x2]
        XCTAssertTrue(Bench.isAllowed(signingInformation: adHoc))
    }

    func testTheLinkerSignatureOnSwiftBuildOutputIsAllowed() {
        // 0x20002: ad hoc and linker-signed.
        XCTAssertTrue(Bench.isAllowed(signingInformation: ["identifier": "Takes", "flags": 0x20002]))
    }

    func testAnUnsignedBuildIsAllowed() {
        XCTAssertTrue(Bench.isAllowed(signingInformation: [:]))
    }

    func testAnEmptyTeamIdentifierCountsAsNone() {
        XCTAssertTrue(Bench.isAllowed(signingInformation: [team: ""]))
    }

    func testASignatureThatCantBeReadIsRefused() {
        XCTAssertFalse(Bench.isAllowed(signingInformation: nil))
    }

    func testARefusedRunReturnsFalseAndStartsNothing() {
        let signed: [String: Any] = [team: "ABCDE12345"]
        // With and without --tone, and with --api, which would read the saved key.
        XCTAssertFalse(Bench.run(arguments: ["Takes", "--bench"], signingInformation: signed))
        XCTAssertFalse(Bench.run(arguments: ["Takes", "--bench", "--tone", "inline"], signingInformation: signed))
        XCTAssertFalse(Bench.run(arguments: ["Takes", "--bench", "--api", "--draft", "x"], signingInformation: signed))
        XCTAssertFalse(Bench.run(arguments: ["Takes", "--bench"], signingInformation: nil))
    }

    func testTheMessageSaysItIsForDevelopmentBuilds() {
        XCTAssertTrue(Bench.developmentOnlyMessage.contains("development builds"))
        XCTAssertFalse(Bench.developmentOnlyMessage.contains("\n"))
    }

    func testTheRunningBinarysSignatureCanBeRead() throws {
        // The Security calls work in this process: the answer is a dictionary, not nil. Whether it is allowed
        // depends on who signed the test runner, so that isn't asserted.
        let information = try XCTUnwrap(Bench.currentSigningInformation())
        XCTAssertEqual(Bench.isAllowed(signingInformation: information), (information[team] as? String ?? "").isEmpty)
    }
}

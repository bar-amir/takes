import Foundation
import XCTest
@testable import Takes

/// Every translation in `Resources/Localizations` must load, and each translated string must take the same values
/// (%@, %lld, in any order) as its English key, or the app would show the wrong value or crash when formatting it.
final class LocalizationTests: XCTestCase {
    private static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Localizations")

    private func table(_ language: String, _ name: String = "Localizable") throws -> [String: String] {
        let url = Self.folder.appendingPathComponent("\(language).lproj/\(name).strings")
        let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], "\(language).lproj/\(name).strings doesn't load")
        return table
    }

    private var languages: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Self.folder.path)) ?? []
        return names.filter { $0.hasSuffix(".lproj") }.map { String($0.dropLast(6)) }.sorted()
    }

    func testEnglishIsThere() throws {
        XCTAssertTrue(languages.contains("en"))
        XCTAssertGreaterThan(try table("en").count, 100)
    }

    func testEveryTranslationLoadsAndKeepsItsValues() throws {
        let english = try table("en")
        for language in languages where language != "en" {
            for (key, value) in try table(language) where english[key] != nil {
                XCTAssertEqual(Self.specifiers(value), Self.specifiers(key), "\(language): “\(key)” → “\(value)”")
            }
        }
    }

    func testPermissionTextsAreTranslatedWhereTheAppIs() throws {
        for language in languages where language != "en" {
            let info = try table(language, "InfoPlist")
            XCTAssertNotNil(info["NSMicrophoneUsageDescription"], language)
            XCTAssertNotNil(info["NSSpeechRecognitionUsageDescription"], language)
        }
    }

    func testSpecifiersReadPositions() {
        XCTAssertEqual(Self.specifiers("%@ of %lld"), [1: "@", 2: "lld"])
        XCTAssertEqual(Self.specifiers("%2$lld de %1$@ · 100%%"), [1: "@", 2: "lld"])
    }

    /// The format specifiers in a string by position ("%2$@" is position 2), ignoring "%%".
    static func specifiers(_ string: String) -> [Int: String] {
        let pattern = try! NSRegularExpression(pattern: #"%(?:(\d+)\$)?[-+0#]*\d*(?:\.\d+)?(ll|l|h|hh|q|z|t|j)?([@dDuUxXoOfFeEgGcCsSaAp%])"#)
        var found: [Int: String] = [:]
        var position = 0
        let range = NSRange(string.startIndex..., in: string)
        for match in pattern.matches(in: string, range: range) {
            let type = Range(match.range(at: 3), in: string).map { String(string[$0]) } ?? ""
            if type == "%" { continue }
            position += 1
            let index = Range(match.range(at: 1), in: string).flatMap { Int(string[$0]) } ?? position
            let length = Range(match.range(at: 2), in: string).map { String(string[$0]) } ?? ""
            found[index] = length + type
        }
        return found
    }

    func testContentDirectionFollowsTheFirstLetter() {
        XCTAssertTrue(ContentDirection.isRightToLeft("שלום, can you send it?"))
        XCTAssertTrue(ContentDirection.isRightToLeft("3 مرحبا"))
        XCTAssertFalse(ContentDirection.isRightToLeft("Thursday works, תודה"))
        XCTAssertFalse(ContentDirection.isRightToLeft(""))
    }
}

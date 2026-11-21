import AppKit
import XCTest

@testable import Takes

/// A take pasted into Slack keeps the mentions, links and styles it still has word for word: Slack's own copy of
/// the draft says what they were, and the take goes back in Slack's clipboard format with them marked again.
final class SlackTextTests: XCTestCase {
    private func mention(_ label: String, id: String) -> [String: Any] {
        ["insert": label, "attributes": ["slackmention": ["id": id, "label": label]]]
    }
    private func link(_ text: String, to url: String) -> [String: Any] { ["insert": text, "attributes": ["link": url]] }
    private func plain(_ text: String) -> [String: Any] { ["insert": text] }

    /// What Slack's ⌘C writes for a message: `{"ops": [...]}`.
    private func copied(_ ops: [[String: Any]]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: ["ops": ops]), encoding: .utf8)!
    }

    /// The take's inserts, as (text, attributes).
    private func ops(_ take: String, from draft: [[String: Any]]) -> NSArray? {
        guard let delta = SlackText.delta(for: take, keeping: SlackText.runs(in: copied(draft))) else { return nil }
        let object = try! JSONSerialization.jsonObject(with: Data(delta.utf8)) as! [String: Any]
        return object["ops"] as? NSArray
    }

    private let draft: [[String: Any]] = [
        ["insert": "@evan", "attributes": ["slackmention": ["id": "U1EVAN", "label": "@evan"]]],
        ["insert": " "],
        ["insert": "@Gidi Cohen", "attributes": ["slackmention": ["id": "U2GIDI", "label": "@Gidi Cohen"]]],
        ["insert": " can u look at "],
        ["insert": "the doc", "attributes": ["link": "https://example.com/doc"]],
        ["insert": " today, its "],
        ["insert": "urgent", "attributes": ["bold": true]],
    ]

    // MARK: What a take keeps

    func testMentionsAtTheStartStayMentions() {
        let take = "@Evan @Gidi Cohen, could you look at the doc today? It's urgent."
        XCTAssertEqual(
            ops(take, from: draft),
            [
                // The person's name as Slack has it, though the take began the sentence with a capital.
                mention("@evan", id: "U1EVAN"), plain(" "), mention("@Gidi Cohen", id: "U2GIDI"), plain(", could you look at "),
                link("the doc", to: "https://example.com/doc"), plain(" today? It's "), ["insert": "urgent", "attributes": ["bold": true]],
                plain("."),
            ] as NSArray)
    }

    func testTheTakeItselfIsWhatIsPasted() {
        let take = "Hey @evan, when you have a minute: the doc needs a look.\n\nThanks!"
        let pasted = (ops(take, from: draft) as? [[String: Any]])?.compactMap { $0["insert"] as? String }.joined()
        XCTAssertEqual(pasted, take, "marking a mention or a link never changes the words")
    }

    func testALinkKeepsTheCaseTheTakeWroteItIn() {
        let take = "The doc is ready."
        XCTAssertEqual(ops(take, from: draft), [link("The doc", to: "https://example.com/doc"), plain(" is ready.")] as NSArray)
    }

    func testATakeThatKeptNothingIsPastedPlain() {
        XCTAssertNil(ops("Could you both review the document this afternoon?", from: draft))
        XCTAssertNil(ops("anything", from: [plain("just words")]))
        XCTAssertEqual(SlackText.runs(in: "not json").count, 0)
    }

    func testOnlyWholeWordsMatch() {
        let evan = [mention("@Evan", id: "U1")]
        XCTAssertNil(ops("Ask @Evans, or write to bob@evan.com", from: evan), "another name, and an address")
        XCTAssertEqual(ops("That's @Evan's call.", from: evan), [plain("That's "), mention("@Evan", id: "U1"), plain("'s call.")] as NSArray)
        XCTAssertNil(ops("There is nothing to add.", from: [link("here", to: "https://example.com")]), "\"here\" inside \"There\"")
    }

    func testEveryPlaceTheTakeNamesAPersonIsTheMention() {
        let take = "@Evan, the doc is ready. Thanks @Evan!"
        XCTAssertEqual(
            ops(take, from: [mention("@Evan", id: "U1"), plain(" see the doc")]),
            [mention("@Evan", id: "U1"), plain(", the doc is ready. Thanks "), mention("@Evan", id: "U1"), plain("!")] as NSArray)
    }

    func testALinkIsGivenOutOnlyAsOftenAsTheDraftHadIt() {
        let take = "Click here, not here."
        XCTAssertEqual(
            ops(take, from: [plain("see "), link("here", to: "https://example.com/a")]),
            [plain("Click "), link("here", to: "https://example.com/a"), plain(", not here.")] as NSArray)
    }

    func testTheSameWordsWithDifferentTargetsKeepTheirOrder() {
        let two = [link("here", to: "https://example.com/a"), plain(" and "), link("here", to: "https://example.com/b")]
        XCTAssertEqual(
            ops("Look here first, then here.", from: two),
            [plain("Look "), link("here", to: "https://example.com/a"), plain(" first, then "), link("here", to: "https://example.com/b"), plain(".")]
                as NSArray)
    }

    func testTheLongerPhraseWinsOverOneInsideIt() {
        let both: [[String: Any]] = [
            link("the launch doc", to: "https://example.com/launch"), plain(" is not a "), ["insert": "doc", "attributes": ["code": true]],
        ]
        XCTAssertEqual(
            ops("Read the launch doc.", from: both), [plain("Read "), link("the launch doc", to: "https://example.com/launch"), plain(".")] as NSArray)
    }

    func testLineStylesAreLeftOutAndAStyledRunIsSplitByLine() {
        let list: [[String: Any]] = [
            plain("first"), ["insert": "\n", "attributes": ["list": "bullet"]],
            ["insert": "bold one\nbold two ", "attributes": ["bold": true, "italic": NSNull()]],
        ]
        XCTAssertEqual(SlackText.runs(in: copied(list)).map(\.text), ["bold one", "bold two"])
        XCTAssertEqual(SlackText.runs(in: copied(list)).first?.attributes as NSDictionary?, ["bold": true])
    }

    func testAScriptWithoutSpacesBetweenWordsStillMatches() {
        XCTAssertEqual(
            ops("@田中さん、資料を見てください", from: [mention("@田中", id: "U1"), plain("さん")]),
            [mention("@田中", id: "U1"), plain("さん、資料を見てください")] as NSArray)
    }

    // MARK: The clipboard

    private func scratchPasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.baramir.takes.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        addTeardownBlock { pasteboard.releaseGlobally() }
        return pasteboard
    }

    func testTheTakeGoesBackInSlacksOwnFormat() throws {
        let pasteboard = scratchPasteboard()
        pasteboard.setString("@evan can u look", forType: .string)
        pasteboard.setData(ChromiumCustomData.encode([SlackText.format: copied(draft), "text": "@evan can u look"]), forType: ChromiumCustomData.type)

        let data = try XCTUnwrap(SlackText.clipboardData(for: "@Evan, could you take a look?", copied: pasteboard))
        let formats = ChromiumCustomData.decode(data)
        XCTAssertEqual(Array(formats.keys), [SlackText.format], "only Slack's format, next to the plain text")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(formats[SlackText.format]).utf8)) as? [String: Any])
        XCTAssertEqual(object["ops"] as? NSArray, [mention("@evan", id: "U1EVAN"), plain(", could you take a look?")] as NSArray)
    }

    func testACopyWithoutSlacksFormatGivesNothing() {
        let pasteboard = scratchPasteboard()
        pasteboard.setString("@evan can u look", forType: .string)
        XCTAssertNil(SlackText.clipboardData(for: "@Evan, could you take a look?", copied: pasteboard))
    }

    func testOnlySlackIsAskedForItsFormat() {
        XCTAssertFalse(SlackText.applies(to: nil))
        XCTAssertFalse(SlackText.applies(to: FocusSnapshot(app: nil, text: "hi", source: .field, caretRect: nil)))
    }

    // MARK: Chromium's custom clipboard data

    private func utf16(_ text: String) -> [UInt8] { text.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] } }

    /// Byte for byte what Chromium put on the clipboard (as `org.chromium.web-custom-data`) when a page's copy
    /// handler called `clipboardData.setData("slack/texty", …)` with this text.
    func testReadsAndWritesWhatChromiumWrites() {
        let texty = #"{"ops":[{"insert":"@Evan","attributes":{"slackmention":{"id":"U1","label":"@Evan"}}},{"insert":" hi 😀 é"}]}"#
        var bytes: [UInt8] = [0xFC, 0, 0, 0, 1, 0, 0, 0]  // 252 bytes follow the size; 1 entry
        bytes += [11, 0, 0, 0] + utf16("slack/texty") + [0, 0]  // 11 UTF-16 units, padded to 4 bytes
        bytes += [108, 0, 0, 0] + utf16(texty)
        XCTAssertEqual(bytes.count, 256)

        XCTAssertEqual(ChromiumCustomData.decode(Data(bytes)), ["slack/texty": texty])
        XCTAssertEqual(ChromiumCustomData.encode(["slack/texty": texty]), Data(bytes))
    }

    func testSeveralFormatsRoundTrip() {
        let formats = ["slack/texty": "{\"ops\":[]}", "text": "odd", "public.utf8-plain-text": ""]
        XCTAssertEqual(ChromiumCustomData.decode(ChromiumCustomData.encode(formats)), formats)
    }

    func testDataThatIsNotLaidOutThatWayGivesNothing() {
        XCTAssertEqual(ChromiumCustomData.decode(Data()), [:])
        XCTAssertEqual(ChromiumCustomData.decode(Data([1, 2, 3])), [:])
        XCTAssertEqual(ChromiumCustomData.decode(Data([8, 0, 0, 0, 2, 0, 0, 0, 200, 0, 0, 0])), [:], "a string longer than the data")
        let whole = ChromiumCustomData.encode(["slack/texty": "{\"ops\":[]}"])
        XCTAssertEqual(ChromiumCustomData.decode(whole.dropLast(6)), [:], "cut short")
    }
}

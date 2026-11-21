import AppKit
import XCTest

@testable import Takes

/// A take pasted into a mail, docs or notes app, or a web page in a browser, keeps the links and styles it still has
/// word for word: the app's own copy of the draft (HTML or RTF) says what they were, and the take goes back as HTML
/// with them marked again.
final class RichTextTests: XCTestCase {
    private typealias Style = RichText.Style

    private func runs(_ html: String) -> [RichText.Run] { RichText.runs(in: RichText.segments(html: html)) }

    private func link(_ url: String) -> Style { Style(link: url) }
    private var bold: Style { Style(bold: true) }

    // MARK: Reading a copy

    func testGmailLinksAndBoldAreRuns() {
        let copied = #"<meta charset="utf-8"><div dir="ltr">pls check <a href="https://example.com/doc?a=1&amp;b=2">the launch doc</a> by <b>Friday</b></div>"#
        XCTAssertEqual(
            runs(copied),
            [
                RichText.Run(text: "the launch doc", style: link("https://example.com/doc?a=1&b=2")),
                RichText.Run(text: "Friday", style: bold),
            ])
    }

    func testGoogleDocsWrapperThatIsNotBoldIsNotBold() {
        // Google Docs wraps every copy in a <b> it makes normal weight, and styles spans inline.
        let copied =
            #"<meta charset="utf-8"><b style="font-weight:normal;" id="docs-internal-guid-1"><p dir="ltr">"#
            + #"<span style="font-weight:400;">The plan is </span>"#
            + #"<span style="font-weight:700;">final</span><span style="font-weight:400;"> and </span><span style="font-style:italic;font-weight:400;">signed</span>"#
            + #"</p></b>"#
        XCTAssertEqual(runs(copied), [RichText.Run(text: "final", style: bold), RichText.Run(text: "signed", style: Style(italic: true))])
    }

    func testStylesSplitByAnotherAttributeAreOneRun() {
        let copied = #"<a href="https://x.com"><span style="color:red">the </span><span style="color:blue">doc</span></a>"#
        XCTAssertEqual(runs(copied), [RichText.Run(text: "the doc", style: link("https://x.com"))])
    }

    func testAStyleTheWholeCopyHasIsTheBoxsLookNotAMark() {
        XCTAssertEqual(runs(#"<span style="font-family:Menlo">let x = 1</span>"#), [])
        XCTAssertEqual(runs(#"<b>all <i>of</i> it</b>"#), [RichText.Run(text: "of", style: Style(italic: true))])
    }

    func testHeadStylesScriptsAndCommentsAreNotText() {
        let copied = "<!DOCTYPE html><html><head><title>Mail</title><style>b { color: red }</style></head><body><!--StartFragment-->"
            + "<script>var a = '<b>no</b>'</script>see <u>this</u><!--EndFragment--></body></html>"
        XCTAssertEqual(runs(copied), [RichText.Run(text: "this", style: Style(underline: true))])
    }

    func testCharacterReferencesAndSpacesAreDecoded() {
        let copied = "<b>Tom&nbsp;&amp;&#32;Jerry&#x2019;s</b> show\n   is <i>on</i>"
        XCTAssertEqual(runs(copied).map(\.text), ["Tom & Jerry\u{2019}s", "on"])
    }

    func testALinkLooksUnderlinedWithoutBeingUnderlined() {
        XCTAssertEqual(runs(#"see <a href="https://x.com"><u>here</u></a> now"#), [RichText.Run(text: "here", style: link("https://x.com"))])
    }

    func testAScriptLinkIsNotALink() {
        XCTAssertEqual(runs(#"click <a href="javascript:alert(1)">here</a> now"#), [])
    }

    func testARunEndsAtALineBreak() {
        XCTAssertEqual(runs("<b>one<br>two</b> three").map(\.text), ["one", "two"])
    }

    func testRTFFromMailOrNotes() {
        let text = NSMutableAttributedString(string: "Send ", attributes: [.font: NSFont.systemFont(ofSize: 13)])
        text.append(NSAttributedString(string: "the deck", attributes: [.font: NSFont.systemFont(ofSize: 13), .link: URL(string: "https://example.com/deck")!]))
        text.append(NSAttributedString(string: " today", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]))
        let runs = RichText.runs(in: RichText.segments(text))
        XCTAssertEqual(runs, [RichText.Run(text: "the deck", style: link("https://example.com/deck")), RichText.Run(text: "today", style: bold)])
    }

    // MARK: Writing the take

    func testTheTakeKeepsWhatItStillHas() throws {
        let copied = #"pls check <a href="https://example.com/doc">the doc</a> by <b>Friday</b>, its <i>urgent</i>"#
        let html = try XCTUnwrap(RichText.html(for: "Could you check the doc by Friday?", keeping: runs(copied)))
        XCTAssertEqual(html, #"<meta charset="utf-8"><div>Could you check <a href="https://example.com/doc">the doc</a> by <b>Friday</b>?</div>"#)
    }

    func testEachLineIsADivAndTextIsEscaped() throws {
        let html = try XCTUnwrap(RichText.html(for: "Hi,\n\nThe doc <draft> & notes.", keeping: [RichText.Run(text: "the doc", style: bold)]))
        XCTAssertEqual(html, #"<meta charset="utf-8"><div>Hi,</div><div><br></div><div><b>The doc</b> &lt;draft&gt; &amp; notes.</div>"#)
    }

    func testAnAddressIsEscapedInTheLink() throws {
        let html = try XCTUnwrap(RichText.html(for: "See here.", keeping: [RichText.Run(text: "here", style: link(#"https://x.com/?q="a"&b"#))]))
        XCTAssertTrue(html.contains(#"<a href="https://x.com/?q=&quot;a&quot;&amp;b">here</a>"#))
    }

    func testATakeThatKeptNothingIsPastedPlain() {
        XCTAssertNil(RichText.html(for: "Could you review the document?", keeping: runs(#"check <a href="https://x.com">the doc</a>"#)))
        XCTAssertNil(RichText.html(for: "anything", keeping: []))
    }

    func testARunIsKeptNoMoreOftenThanTheDraftHadIt() throws {
        let html = try XCTUnwrap(RichText.html(for: "The doc, the doc.", keeping: [RichText.Run(text: "the doc", style: bold)]))
        XCTAssertEqual(html, #"<meta charset="utf-8"><div><b>The doc</b>, the doc.</div>"#)
    }

    // MARK: From the clipboard

    private func pasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.baramir.takes.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    func testTheClipboardsHTMLIsReadFirst() throws {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        board.setString("check the doc", forType: .string)
        board.setString(#"check <a href="https://x.com">the doc</a>"#, forType: .html)
        let html = try XCTUnwrap(RichText.clipboardHTML(for: "Please check the doc.", copied: board))
        XCTAssertTrue(html.contains(#"<a href="https://x.com">the doc</a>"#))
    }

    func testTheClipboardsRTFIsReadWhenThereIsNoHTML() throws {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        // As Mail or Notes would copy it, in fonts that keep their weight through RTF.
        let regular = try XCTUnwrap(NSFont(name: "Helvetica", size: 12))
        let heavy = try XCTUnwrap(NSFont(name: "Helvetica-Bold", size: 12))
        let text = NSMutableAttributedString(string: "check ", attributes: [.font: regular])
        text.append(NSAttributedString(string: "the doc", attributes: [.font: heavy]))
        let rtf = try XCTUnwrap(text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:]))
        board.setData(rtf, forType: .rtf)
        let html = try XCTUnwrap(RichText.clipboardHTML(for: "Please check the doc.", copied: board))
        XCTAssertTrue(html.contains("<b>the doc</b>"))
    }

    func testAPlainCopyHasNothingToKeep() {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        board.setString("check the doc", forType: .string)
        XCTAssertNil(RichText.clipboardHTML(for: "Please check the doc.", copied: board))
    }

    func testAnyAppButSlackGetsTheTakeAsHTML() {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        board.setString(#"check <a href="https://x.com">the doc</a>"#, forType: .html)
        XCTAssertEqual(
            KeptFormatting.formatted("Please check the doc.", copied: board, target: nil),
            .html(#"<meta charset="utf-8"><div>Please check <a href="https://x.com">the doc</a>.</div>"#))
    }

    func testTheAppsItCovers() {
        XCTAssertFalse(RichText.applies(to: nil))
        XCTAssertFalse(RichText.applies(to: FocusSnapshot(app: nil, text: "", source: .field, caretRect: nil)))
        XCTAssertTrue(RichText.bundleIDs.isSuperset(of: ["com.google.Chrome", "com.apple.Safari", "com.apple.mail", "com.microsoft.Outlook", "notion.id"]))
        XCTAssertFalse(RichText.bundleIDs.contains(SlackText.bundleID), "Slack has its own format")
    }
}

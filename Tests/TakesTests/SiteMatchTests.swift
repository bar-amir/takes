import AppKit
import ApplicationServices
import XCTest

@testable import Takes

/// Presets picked by website: reading the page's address, matching domains, and what wins over the browser's preset.
final class SiteMatchTests: XCTestCase {
    func testDomainsMatchTheirSubdomains() {
        let outlook = AppRef.site("outlook.office.com", "outlook.live.com", name: "Outlook web")
        XCTAssertTrue(outlook.isSite)
        XCTAssertEqual(outlook.siteDomains, ["outlook.office.com", "outlook.live.com"])
        XCTAssertTrue(outlook.matches(bundleID: nil, site: "outlook.live.com"))
        XCTAssertTrue(outlook.matches(bundleID: nil, site: "eu.outlook.office.com"))
        XCTAssertFalse(outlook.matches(bundleID: nil, site: "notoutlook.live.com"))
        XCTAssertFalse(outlook.matches(bundleID: nil, site: nil))
        XCTAssertFalse(outlook.matches(bundleID: "site:outlook.live.com", site: nil), "A website never matches as an app")

        let mail = AppRef(bundleID: "com.apple.mail", name: "Mail")
        XCTAssertNil(mail.siteDomains)
        XCTAssertTrue(mail.matches(bundleID: "com.apple.mail", site: "mail.google.com"))
        XCTAssertFalse(mail.matches(bundleID: nil, site: nil))
    }

    func testTypedAddresses() {
        XCTAssertEqual(AppRef.domain(from: "https://mail.google.com/mail/u/0/#inbox"), "mail.google.com")
        XCTAssertEqual(AppRef.domain(from: "  Gmail.com "), "gmail.com")
        XCTAssertEqual(AppRef.domain(from: "www.linkedin.com/feed"), "linkedin.com")
        XCTAssertNil(AppRef.domain(from: "gmail"))
        XCTAssertNil(AppRef.domain(from: ""))
    }

    /// A preset for the website beats the one for the browser; the browser's still follows in the picker.
    func testWebsiteComesBeforeTheBrowser() {
        let browser = Preset(id: "b", name: "In Chrome", colorHex: "#2F55E0", instruction: "x",
                             apps: [AppRef(bundleID: "com.google.Chrome", name: "Chrome")])
        let gmail = Preset(id: "g", name: "Gmail", colorHex: "#2F55E0", instruction: "x", apps: [.site("mail.google.com", name: "Gmail")])
        let other = Preset(id: "o", name: "Other", colorHex: "#2F55E0", instruction: "x")
        let presets = [browser, gmail, other]
        XCTAssertEqual(Store.pickedFirst(presets, bundleID: "com.google.Chrome", site: "mail.google.com").map(\.id), ["g", "b"])
        XCTAssertEqual(Store.pickedFirst(presets, bundleID: "com.google.Chrome", site: "example.com").map(\.id), ["b"])
        XCTAssertEqual(Store.pickedFirst(presets, bundleID: "com.apple.Safari", site: "mail.google.com").map(\.id), ["g"])
        XCTAssertEqual(Store.pickedFirst(presets, bundleID: nil, site: nil).map(\.id), [])
    }

    /// In an app that isn't a browser but shows a web page (Slack's desktop app), the preset tied to the app wins.
    func testTheUsersAppBeatsAWebsiteInsideThatApp() {
        let mine = Preset(id: "m", name: "My Slack", colorHex: "#2F55E0", instruction: "x",
                          apps: [AppRef(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")])
        let starter = Preset(id: "s", name: "Slack message", colorHex: "#2F55E0", instruction: "x", apps: [.site("app.slack.com", name: "Slack")])
        let notBrowser: (String) -> Bool = { _ in false }
        XCTAssertEqual(
            Store.pickedFirst([starter, mine], bundleID: "com.tinyspeck.slackmacgap", site: "app.slack.com", isBrowser: notBrowser).map(\.id), ["m", "s"])
        XCTAssertEqual(Store.pickedFirst([starter], bundleID: "com.tinyspeck.slackmacgap", site: "app.slack.com", isBrowser: notBrowser).map(\.id), ["s"])
        XCTAssertTrue(Browsers.contains("com.google.Chrome"))
        XCTAssertFalse(Browsers.contains("com.tinyspeck.slackmacgap"))
    }

    /// The page is the outermost web area above the text box: a frame inside it doesn't count.
    func testSiteIsTheTabsPage() {
        // field → frame (web area) → group → page (web area) → window. Each element is told apart by a made-up pid.
        let parents: [pid_t: pid_t] = [11: 12, 12: 13, 13: 14, 14: 15]
        var values: [pid_t: [String: CFTypeRef]] = [
            12: [kAXRoleAttribute: "AXWebArea" as CFString, "AXURL": URL(string: "https://ads.example.net/frame")! as CFURL],
            14: [kAXRoleAttribute: "AXWebArea" as CFString, "AXURL": URL(string: "https://mail.google.com/mail/u/0/")! as CFURL],
        ]
        func client() -> AXClient {
            AXClient(
                attribute: { element, attribute in
                    var pid: pid_t = 0
                    AXUIElementGetPid(element, &pid)
                    if attribute == kAXParentAttribute, let parent = parents[pid] { return (AXUIElementCreateApplication(parent) as CFTypeRef, .success) }
                    if let value = values[pid]?[attribute] { return (value, .success) }
                    return (nil, .attributeUnsupported)
                },
                parameterized: { _, _, _ in nil }, isSettable: { _, _ in nil }, set: { _, _, _ in .success })
        }
        FocusReader.ax = client()
        defer { FocusReader.ax = .live }
        let field = AXUIElementCreateApplication(11)
        XCTAssertEqual(FocusReader.site(around: field), "mail.google.com")

        values[14]?["AXURL"] = URL(string: "file:///Users/me/notes.html")! as CFURL
        FocusReader.ax = client()
        XCTAssertEqual(FocusReader.site(around: field), "ads.example.net", "Only web addresses count")

        values = [:]
        FocusReader.ax = client()
        XCTAssertNil(FocusReader.site(around: field), "Not on a web page")
    }
}

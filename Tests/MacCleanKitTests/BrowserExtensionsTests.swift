import XCTest
@testable import MacCleanKit

final class BrowserExtensionsTests: XCTestCase {
    func testParsesChromeFamilyManifest() throws {
        let json = """
        {"name":"Nice Tab","version":"1.2.0","manifest_version":3}
        """.data(using: .utf8)!
        let record = try XCTUnwrap(BrowserExtensionManifest.chromeFamily(
            json: json,
            extensionID: "abcdefghijklmnopqrstuvwxyzabcdef",
            browser: .chrome,
            path: "/Users/me/Library/Application Support/Google/Chrome/Default/Extensions/abcdefghijklmnopqrstuvwxyzabcdef",
            installedAt: Date(timeIntervalSince1970: 50)
        ))
        XCTAssertEqual(record.name, "Nice Tab")
        XCTAssertEqual(record.browser, .chrome)
        XCTAssertEqual(record.installedAt, Date(timeIntervalSince1970: 50))
        XCTAssertFalse(record.isMalicious)
    }

    func testLocalizedChromeNameFallsBackToDefaultLocale() throws {
        let json = """
        {"name":"__MSG_extName__","default_locale":"en","manifest_version":3}
        """.data(using: .utf8)!
        let messages = """
        {"extName":{"message":"Localized Name"}}
        """.data(using: .utf8)!
        let record = try XCTUnwrap(BrowserExtensionManifest.chromeFamily(
            json: json,
            extensionID: "bbb",
            browser: .brave,
            path: "/ext",
            installedAt: nil,
            messagesJSON: messages
        ))
        XCTAssertEqual(record.name, "Localized Name")
        XCTAssertEqual(record.browser, .brave)
    }

    func testFlagsKnownMaliciousExtensionIDs() throws {
        let id = MaliciousExtensionIDs.known.first!
        let json = #"{"name":"Search Helper","manifest_version":3}"#.data(using: .utf8)!
        let record = try XCTUnwrap(BrowserExtensionManifest.chromeFamily(
            json: json,
            extensionID: id,
            browser: .edge,
            path: "/ext",
            installedAt: nil
        ))
        XCTAssertTrue(record.isMalicious)
        XCTAssertFalse(MaliciousExtensionIDs.contains("not-a-real-extension-id"))
    }

    func testParsesFirefoxExtensionsJSON() throws {
        let json = """
        {"addons":[
          {"id":"uBlock0@raymondhill.net","type":"extension","defaultLocale":{"name":"uBlock Origin"},"installDate":1700000000000,"path":"/profile/extensions/uBlock0@raymondhill.net.xpi"},
          {"id":"langpack","type":"locale","defaultLocale":{"name":"English"},"installDate":1}
        ]}
        """.data(using: .utf8)!
        let records = BrowserExtensionManifest.firefox(json: json, profilePath: "/profile")
        XCTAssertEqual(records.map(\.name), ["uBlock Origin"])
        XCTAssertEqual(records[0].browser, .firefox)
        XCTAssertEqual(records[0].installedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testRemovalPlan() {
        let chrome = BrowserExtensionRecord(
            browser: .chrome, identifier: "abc", name: "A", installedAt: nil,
            path: "/Chrome/Extensions/abc", isMalicious: false
        )
        let safari = BrowserExtensionRecord(
            browser: .safari, identifier: "com.example.ext", name: "S", installedAt: nil,
            path: "/Safari/Extensions/S", isMalicious: false
        )
        XCTAssertEqual(
            BrowserExtensionRemoval.plan(record: chrome, browserIsRunning: true),
            .openExtensionsPage(browser: .chrome)
        )
        XCTAssertEqual(
            BrowserExtensionRemoval.plan(record: chrome, browserIsRunning: false),
            .deleteFolder("/Chrome/Extensions/abc")
        )
        XCTAssertEqual(
            BrowserExtensionRemoval.plan(record: safari, browserIsRunning: false),
            .readOnly
        )
    }

    func testSafariListingIsNameAndDateOnly() {
        let records = BrowserExtensionManifest.safariExtensions(
            [
                BrowserExtensionManifest.SafariExtensionFile(
                    name: "Ad Guard",
                    path: "/Users/me/Library/Safari/Extensions/Ad Guard.safariextz",
                    installedAt: Date(timeIntervalSince1970: 9)
                )
            ]
        )
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].browser, .safari)
        XCTAssertEqual(records[0].name, "Ad Guard")
        XCTAssertEqual(
            BrowserExtensionRemoval.plan(record: records[0], browserIsRunning: false),
            .readOnly
        )
    }
}

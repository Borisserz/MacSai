import XCTest
@testable import MacClean

final class DeepLinkRoutingTests: XCTestCase {
    func testDeepLinkIDRoundTrips() {
        XCTAssertEqual(SidebarItem.systemJunk.deepLinkID, "system-junk")
        XCTAssertEqual(SidebarItem(deepLinkID: "system-junk"), .systemJunk)
        XCTAssertEqual(SidebarItem(deepLinkID: "trash-bins"), .trashBins)
        XCTAssertEqual(SidebarItem.wifiNetworks.deepLinkID, "wifi-networks")
        XCTAssertEqual(SidebarItem(deepLinkID: "wifi-networks"), .wifiNetworks)
        XCTAssertEqual(SidebarItem.appPermissions.deepLinkID, "app-permissions")
        XCTAssertEqual(SidebarItem(deepLinkID: "app-permissions"), .appPermissions)
        XCTAssertEqual(SidebarItem.extensions.deepLinkID, "extensions")
        XCTAssertEqual(SidebarItem(deepLinkID: "extensions"), .extensions)
        XCTAssertEqual(SidebarItem.cleanHistory.deepLinkID, "clean-history")
        XCTAssertEqual(SidebarItem(deepLinkID: "clean-history"), .cleanHistory)
        XCTAssertNil(SidebarItem(deepLinkID: "nonsense"))
    }
}

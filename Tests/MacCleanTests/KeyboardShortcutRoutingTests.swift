import XCTest
@testable import MacClean

final class KeyboardShortcutRoutingTests: XCTestCase {

    func testShortcutDigitsMapFirstNineModulesExcludingSettings() {
        let items = SidebarItem.keyboardShortcutItems
        XCTAssertEqual(items.count, min(9, SidebarItem.allCases.filter { $0 != .settings }.count))
        XCTAssertFalse(items.contains(.settings))
        XCTAssertEqual(items.first, .smartScan)
        XCTAssertEqual(SidebarItem.item(forShortcutDigit: 1), .smartScan)
        XCTAssertEqual(SidebarItem.item(forShortcutDigit: 2), .systemJunk)
        XCTAssertEqual(SidebarItem.item(forShortcutDigit: 9), items[8])
    }

    func testShortcutDigitsRejectOutOfRange() {
        XCTAssertNil(SidebarItem.item(forShortcutDigit: 0))
        XCTAssertNil(SidebarItem.item(forShortcutDigit: -1))
        XCTAssertNil(SidebarItem.item(forShortcutDigit: 10))
        XCTAssertNil(SidebarItem.item(forShortcutDigit: 99))
    }

    func testAppStateShortcutNoncesIncrement() {
        let state = AppState()
        XCTAssertEqual(state.scanShortcutNonce, 0)
        XCTAssertEqual(state.cleanShortcutNonce, 0)
        state.requestScanShortcut()
        state.requestScanShortcut()
        state.requestCleanShortcut()
        XCTAssertEqual(state.scanShortcutNonce, 2)
        XCTAssertEqual(state.cleanShortcutNonce, 1)
    }
}

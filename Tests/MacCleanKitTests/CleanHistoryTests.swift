import XCTest
@testable import MacCleanKit

final class CleanHistoryTests: XCTestCase {
    func testRestorePlanMovesBackOnlyWhenTrashRemainsAndOriginalIsFree() {
        let item = CleanHistoryItem(
            id: UUID(),
            originalPath: "/Users/me/Library/Caches/com.foo",
            trashPath: "/Users/me/.Trash/com.foo",
            bytes: 10
        )
        XCTAssertEqual(
            CleanHistoryRestore.plan(item: item, trashExists: true, originalExists: false),
            .restore(fromTrash: item.trashPath, to: item.originalPath)
        )
        XCTAssertEqual(
            CleanHistoryRestore.plan(item: item, trashExists: false, originalExists: false),
            .skippedEmptied(originalPath: item.originalPath)
        )
        XCTAssertEqual(
            CleanHistoryRestore.plan(item: item, trashExists: true, originalExists: true),
            .skippedReappeared(originalPath: item.originalPath)
        )
    }

    func testSessionRoundTripAndNewestFirst() {
        let older = CleanHistorySession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            date: Date(timeIntervalSince1970: 10),
            items: []
        )
        let newer = CleanHistorySession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            date: Date(timeIntervalSince1970: 20),
            items: [
                CleanHistoryItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                    originalPath: "/a",
                    trashPath: "/Trash/a",
                    bytes: 4
                )
            ]
        )
        let stored = CleanHistoryStore.adding(newer, to: [older])
        let data = try! CleanHistoryStore.encode(stored)
        let decoded = try! CleanHistoryStore.decode(data)
        XCTAssertEqual(decoded.map(\.id), [newer.id, older.id])
        XCTAssertEqual(decoded[0].items[0].originalPath, "/a")
        XCTAssertEqual(decoded[0].items[0].trashPath, "/Trash/a")
    }

    func testRestoreSummaryCountsSkips() {
        let session = CleanHistorySession(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1),
            items: [
                CleanHistoryItem(id: UUID(), originalPath: "/a", trashPath: "/t/a", bytes: 1),
                CleanHistoryItem(id: UUID(), originalPath: "/b", trashPath: "/t/b", bytes: 1),
                CleanHistoryItem(id: UUID(), originalPath: "/c", trashPath: "/t/c", bytes: 1),
            ]
        )
        let existence: [String: Bool] = [
            "/t/a": true, "/a": false,
            "/t/b": false, "/b": false,
            "/t/c": true, "/c": true,
        ]
        let summary = CleanHistoryRestore.summarize(session: session) { existence[$0] ?? false }
        XCTAssertEqual(summary.restored, 1)
        XCTAssertEqual(summary.emptied, 1)
        XCTAssertEqual(summary.reappeared, 1)
        XCTAssertEqual(summary.moves.map(\.to), ["/a"])
    }
}

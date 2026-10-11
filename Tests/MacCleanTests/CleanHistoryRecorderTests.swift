import XCTest
@testable import MacClean
@testable import MacCleanKit

final class CleanHistoryRecorderTests: XCTestCase {
    func testRecordPersistsSessionAndRestoreMovesWhenSafe() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "clean-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            CleanHistoryRecorder.fileURL = MCConstants.cleanHistoryFile
            try? FileManager.default.removeItem(at: dir)
        }

        let historyFile = dir.appending(path: "clean-history.json")
        CleanHistoryRecorder.fileURL = historyFile

        let original = dir.appending(path: "Caches/com.example")
        let trash = dir.appending(path: "Trash/com.example")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try "payload".write(to: trash.appending(path: "file.txt"), atomically: true, encoding: .utf8)

        let session = CleanHistorySession(
            id: UUID(),
            date: Date(),
            items: [
                CleanHistoryItem(
                    id: UUID(),
                    originalPath: original.path(percentEncoded: false),
                    trashPath: trash.path(percentEncoded: false),
                    bytes: 7
                )
            ]
        )
        CleanHistoryRecorder.save([session])

        let loaded = CleanHistoryRecorder.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].items[0].originalPath, original.path(percentEncoded: false))

        let summary = CleanHistoryRecorder.restore(session)
        XCTAssertEqual(summary.restored, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.appending(path: "file.txt").path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: trash.path(percentEncoded: false)))
    }
}

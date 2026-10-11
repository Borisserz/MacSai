import Foundation
import MacCleanKit

/// Persists whole-clean sessions so the user can Restore in one click.
public enum CleanHistoryRecorder {
    /// Override in tests; defaults to the user's clean-history JSON.
    nonisolated(unsafe) public static var fileURL: URL = MCConstants.cleanHistoryFile

    public static func load() -> [CleanHistorySession] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
              let data = try? Data(contentsOf: url),
              let sessions = try? CleanHistoryStore.decode(data)
        else { return [] }
        return sessions
    }

    public static func record(
        trashedItems: [CleaningEngine.TrashedItem],
        now: Date = Date()
    ) {
        guard !trashedItems.isEmpty else { return }
        let session = CleanHistorySession(
            id: UUID(),
            date: now,
            items: trashedItems.map {
                CleanHistoryItem(
                    id: UUID(),
                    originalPath: $0.originalURL.path(percentEncoded: false),
                    trashPath: $0.trashURL.path(percentEncoded: false),
                    bytes: $0.bytes
                )
            }
        )
        let updated = CleanHistoryStore.adding(session, to: load())
        save(updated)
    }

    public static func save(_ sessions: [CleanHistorySession]) {
        let url = fileURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? CleanHistoryStore.encode(sessions) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Applies a restore plan: move trash items back when safe.
    @discardableResult
    public static func restore(_ session: CleanHistorySession) -> CleanHistoryRestoreSummary {
        let fm = FileManager.default
        let summary = CleanHistoryRestore.summarize(session: session) {
            fm.fileExists(atPath: $0)
        }
        for move in summary.moves {
            let from = URL(filePath: move.from)
            let to = URL(filePath: move.to)
            let parent = to.deletingLastPathComponent()
            try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
            do {
                try fm.moveItem(at: from, to: to)
            } catch {
                // Best-effort: leave the trash copy if restore fails.
                continue
            }
        }
        return summary
    }
}

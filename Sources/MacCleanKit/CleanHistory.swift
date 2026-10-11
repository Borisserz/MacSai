import Foundation

public struct CleanHistoryItem: Equatable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let originalPath: String
    public let trashPath: String
    public let bytes: UInt64

    public init(id: UUID, originalPath: String, trashPath: String, bytes: UInt64) {
        self.id = id
        self.originalPath = originalPath
        self.trashPath = trashPath
        self.bytes = bytes
    }
}

public struct CleanHistorySession: Equatable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    public let items: [CleanHistoryItem]

    public init(id: UUID, date: Date, items: [CleanHistoryItem]) {
        self.id = id
        self.date = date
        self.items = items
    }

    public var totalBytes: UInt64 {
        items.reduce(0) { $0 &+ $1.bytes }
    }
}

public enum CleanHistoryRestoreAction: Equatable, Sendable {
    case restore(fromTrash: String, to: String)
    case skippedEmptied(originalPath: String)
    case skippedReappeared(originalPath: String)
}

public struct CleanHistoryRestoreSummary: Equatable, Sendable {
    public struct Move: Equatable, Sendable {
        public let from: String
        public let to: String
        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    public let restored: Int
    public let emptied: Int
    public let reappeared: Int
    public let moves: [Move]

    public init(restored: Int, emptied: Int, reappeared: Int, moves: [Move]) {
        self.restored = restored
        self.emptied = emptied
        self.reappeared = reappeared
        self.moves = moves
    }
}

public enum CleanHistoryRestore {
    public static func plan(
        item: CleanHistoryItem,
        trashExists: Bool,
        originalExists: Bool
    ) -> CleanHistoryRestoreAction {
        if !trashExists {
            return .skippedEmptied(originalPath: item.originalPath)
        }
        if originalExists {
            return .skippedReappeared(originalPath: item.originalPath)
        }
        return .restore(fromTrash: item.trashPath, to: item.originalPath)
    }

    public static func summarize(
        session: CleanHistorySession,
        exists: (String) -> Bool
    ) -> CleanHistoryRestoreSummary {
        var restored = 0
        var emptied = 0
        var reappeared = 0
        var moves: [CleanHistoryRestoreSummary.Move] = []

        for item in session.items {
            switch plan(
                item: item,
                trashExists: exists(item.trashPath),
                originalExists: exists(item.originalPath)
            ) {
            case .restore(let from, let to):
                restored += 1
                moves.append(.init(from: from, to: to))
            case .skippedEmptied:
                emptied += 1
            case .skippedReappeared:
                reappeared += 1
            }
        }

        return CleanHistoryRestoreSummary(
            restored: restored,
            emptied: emptied,
            reappeared: reappeared,
            moves: moves
        )
    }
}

public enum CleanHistoryStore {
    public static let maxSessions = 20

    public static func adding(
        _ session: CleanHistorySession,
        to existing: [CleanHistorySession]
    ) -> [CleanHistorySession] {
        ([session] + existing)
            .sorted { $0.date > $1.date }
            .prefix(maxSessions)
            .map { $0 }
    }

    public static func encode(_ sessions: [CleanHistorySession]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(sessions)
    }

    public static func decode(_ data: Data) throws -> [CleanHistorySession] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([CleanHistorySession].self, from: data)
            .sorted { $0.date > $1.date }
    }
}

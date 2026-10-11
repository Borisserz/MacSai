import Foundation

public enum BrowserKind: String, Equatable, Sendable, CaseIterable, Identifiable {
    case safari
    case chrome
    case brave
    case edge
    case arc
    case firefox

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .brave: "Brave"
        case .edge: "Edge"
        case .arc: "Arc"
        case .firefox: "Firefox"
        }
    }

    public var extensionsPageURL: URL? {
        switch self {
        case .safari: URL(string: "x-apple.systempreferences:com.apple.Safari-Settings.extension")
        case .chrome: URL(string: "chrome://extensions")
        case .brave: URL(string: "brave://extensions")
        case .edge: URL(string: "edge://extensions")
        case .arc: URL(string: "chrome://extensions")
        case .firefox: URL(string: "about:addons")
        }
    }
}

public struct BrowserExtensionRecord: Equatable, Hashable, Sendable, Identifiable {
    public var id: String { "\(browser.rawValue)|\(identifier)" }

    public let browser: BrowserKind
    public let identifier: String
    public let name: String
    public let installedAt: Date?
    public let path: String
    public let isMalicious: Bool

    public init(
        browser: BrowserKind,
        identifier: String,
        name: String,
        installedAt: Date?,
        path: String,
        isMalicious: Bool
    ) {
        self.browser = browser
        self.identifier = identifier
        self.name = name
        self.installedAt = installedAt
        self.path = path
        self.isMalicious = isMalicious
    }
}

/// Curated Chrome-family extension IDs known to ship adware / data-harvesting.
/// Kept small on purpose — same posture as `MalwareSignatures`. Contributors
/// should cite a write-up when adding IDs.
public enum MaliciousExtensionIDs {
    public static let known: Set<String> = [
        // Seeds used by unit tests and reserved for documented adware IDs.
        "badextaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "adwarebbbbbbbbbbbbbbbbbbbbbbbbbb",
    ]

    public static func contains(_ extensionID: String) -> Bool {
        known.contains(extensionID.lowercased())
    }
}

public enum BrowserExtensionRemovalPlan: Equatable, Sendable {
    case openExtensionsPage(browser: BrowserKind)
    case deleteFolder(String)
    case readOnly
}

public enum BrowserExtensionRemoval {
    public static func plan(
        record: BrowserExtensionRecord,
        browserIsRunning: Bool
    ) -> BrowserExtensionRemovalPlan {
        if record.browser == .safari { return .readOnly }
        if browserIsRunning { return .openExtensionsPage(browser: record.browser) }
        return .deleteFolder(record.path)
    }
}

public enum BrowserExtensionManifest {
    public struct SafariExtensionFile: Equatable, Sendable {
        public let name: String
        public let path: String
        public let installedAt: Date?

        public init(name: String, path: String, installedAt: Date?) {
            self.name = name
            self.path = path
            self.installedAt = installedAt
        }
    }

    public static func chromeFamily(
        json: Data,
        extensionID: String,
        browser: BrowserKind,
        path: String,
        installedAt: Date?,
        messagesJSON: Data? = nil
    ) -> BrowserExtensionRecord? {
        struct Manifest: Decodable {
            let name: String?
            let default_locale: String?
        }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: json) else { return nil }
        var name = manifest.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.hasPrefix("__MSG_"), name.hasSuffix("__"), let messagesJSON {
            let key = String(name.dropFirst(6).dropLast(2))
            if let localized = localizedMessage(key: key, from: messagesJSON) {
                name = localized
            }
        }
        if name.isEmpty { name = extensionID }
        let malicious = MaliciousExtensionIDs.contains(extensionID)
            || MalwareSignatures.nameMatchesKnownPattern(name)
        return BrowserExtensionRecord(
            browser: browser,
            identifier: extensionID,
            name: name,
            installedAt: installedAt,
            path: path,
            isMalicious: malicious
        )
    }

    public static func firefox(json: Data, profilePath: String) -> [BrowserExtensionRecord] {
        struct Payload: Decodable {
            struct Addon: Decodable {
                struct Locale: Decodable { let name: String? }
                let id: String
                let type: String?
                let defaultLocale: Locale?
                let installDate: Double?
                let path: String?
            }
            let addons: [Addon]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: json) else { return [] }
        return payload.addons.compactMap { addon in
            guard (addon.type ?? "extension") == "extension" else { return nil }
            let installedAt = addon.installDate.map { Date(timeIntervalSince1970: $0 / 1000) }
            let path = addon.path ?? "\(profilePath)/extensions/\(addon.id)"
            return BrowserExtensionRecord(
                browser: .firefox,
                identifier: addon.id,
                name: addon.defaultLocale?.name ?? addon.id,
                installedAt: installedAt,
                path: path,
                isMalicious: MaliciousExtensionIDs.contains(addon.id)
            )
        }
    }

    public static func safariExtensions(_ files: [SafariExtensionFile]) -> [BrowserExtensionRecord] {
        files.map { file in
            BrowserExtensionRecord(
                browser: .safari,
                identifier: file.path,
                name: file.name,
                installedAt: file.installedAt,
                path: file.path,
                isMalicious: MalwareSignatures.nameMatchesKnownPattern(file.name)
            )
        }
    }

    private static func localizedMessage(key: String, from data: Data) -> String? {
        struct Entry: Decodable { let message: String? }
        guard let dict = try? JSONDecoder().decode([String: Entry].self, from: data) else { return nil }
        return dict[key]?.message
    }
}

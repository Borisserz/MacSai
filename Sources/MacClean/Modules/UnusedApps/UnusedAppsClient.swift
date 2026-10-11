import CoreServices
import Foundation
import MacCleanKit

/// Discovers installed apps and builds `UnusedAppRecord`s with Spotlight
/// last-used dates and support-file footprint.
public struct UnusedAppsClient: Sendable {
    private let discovery = AppDiscovery()
    private let pathFinder = AppPathFinder()

    public init() {}

    public func list(horizon: UnusedAppHorizon) async -> [UnusedAppRecord] {
        let apps = await discovery.discoverApps()
        let records = apps.map { app -> UnusedAppRecord in
            let support = pathFinder.findAssociatedFiles(for: app)
            let supportBytes = support.reduce(UInt64(0)) { $0 &+ $1.size }
            let lastUsed = Self.spotlightLastUsed(at: app.path) ?? app.lastOpened
            let runsInBackground = Self.readsBackgroundRole(at: app.path)
            return UnusedAppRecord(
                name: app.name,
                bundleIdentifier: app.bundleIdentifier,
                path: app.path.path(percentEncoded: false),
                appBytes: app.size,
                supportBytes: supportBytes,
                lastUsed: lastUsed,
                isApple: app.isAppleApp,
                runsInBackground: runsInBackground
            )
        }
        return UnusedApps.unused(from: records, horizon: horizon)
    }

    static func spotlightLastUsed(at url: URL) -> Date? {
        let path = url.path(percentEncoded: false) as CFString
        guard let item = MDItemCreate(nil, path) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    static func readsBackgroundRole(at url: URL) -> Bool {
        let plistURL = url.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return false }
        return AppRuntimeRole.runsInBackground(infoPlist: plist)
    }
}

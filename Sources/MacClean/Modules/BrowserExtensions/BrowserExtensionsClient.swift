import AppKit
import Foundation
import MacCleanKit

public struct BrowserExtensionsClient: Sendable {
    public init() {}

    /// What happened after the user asked to remove an extension.
    public enum RemovalOutcome: Equatable, Sendable {
        case trashed
        case removeInBrowser(BrowserKind)
        case managedByPolicy(BrowserKind)
        case builtIn(BrowserKind)
        case openedSafariSettings
        case refused
        case failed(String)
    }

    public func list() async -> BrowserExtensionScan {
        await Task.detached {
            var records: [BrowserExtensionRecord] = []
            for browser in BrowserKind.chromiumFamily {
                records.append(contentsOf: Self.chromeFamily(browser: browser))
            }
            records.append(contentsOf: Self.firefox())
            let pluginKit = ManagedExtensionsClient.captureStandardOutput(
                of: URL(filePath: "/usr/bin/pluginkit"),
                arguments: ["-m", "-v"]
            )
            records.append(contentsOf: await Self.safari(pluginKitOutput: pluginKit))
            let sorted = records.sorted {
                if $0.isSuspicious != $1.isSuspicious { return $0.isSuspicious }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return BrowserExtensionScan(
                records: sorted,
                safariListed: !pluginKit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }.value
    }

    public func applyRemoval(_ record: BrowserExtensionRecord) async -> RemovalOutcome {
        let running = await Self.browserIsRunning(record)
        switch BrowserExtensionRemoval.plan(record: record, browserIsRunning: running) {
        case .safariSettings:
            await MainActor.run { _ = NSWorkspace.shared.open(ManagedExtensionPolicy.safariSettingsURL) }
            return .openedSafariSettings
        case .managedByPolicy(let browser):
            return .managedByPolicy(browser)
        case .builtIn(let browser):
            return .builtIn(browser)
        case .refuse:
            return .refused
        case .removeInBrowser(let browser):
            await Self.bringForward(browser)
            return .removeInBrowser(browser)
        case .deleteFolder(let path):
            // Re-check right before touching disk: the browser may have been
            // launched while the confirmation was up.
            if await Self.browserIsRunning(record) {
                await Self.bringForward(record.browser)
                return .removeInBrowser(record.browser)
            }
            do {
                try FileManager.default.trashItem(at: URL(filePath: path), resultingItemURL: nil)
                return .trashed
            } catch {
                return .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Running check

    /// Running if any of the browser's apps is open OR its profile lock is
    /// held. Either one blocks deletion.
    private static func browserIsRunning(_ record: BrowserExtensionRecord) async -> Bool {
        let ids = record.browser.bundleIdentifiers
        let appRunning = await MainActor.run {
            NSWorkspace.shared.runningApplications.contains { app in
                app.bundleIdentifier.map(ids.contains) ?? false
            }
        }
        if appRunning { return true }
        switch record.browser {
        case .chrome, .brave, .edge, .arc:
            guard let relative = record.browser.chromiumUserDataRelativePath else { return true }
            return BrowserProfileLock.chromiumUserDataIsLocked(
                MCConstants.userAppSupport.appending(path: relative)
            )
        case .firefox:
            return BrowserProfileLock.firefoxProfileIsLocked(firefoxProfilesRoot.appending(path: record.profile))
        case .safari:
            return false
        }
    }

    @MainActor
    private static func bringForward(_ browser: BrowserKind) async {
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: browser.primaryBundleIdentifier
        ) else { return }
        _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
    }

    // MARK: - Chromium

    private static func chromeFamily(browser: BrowserKind) -> [BrowserExtensionRecord] {
        guard let relative = browser.chromiumUserDataRelativePath else { return [] }
        let fm = FileManager.default
        let base = MCConstants.userAppSupport.appending(path: relative)
        guard let profiles = try? fm.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let forced = forcedExtensionIDs(for: browser)

        var records: [BrowserExtensionRecord] = []
        for profile in profiles {
            let extRoot = profile.appending(path: "Extensions")
            guard let extIDs = try? fm.contentsOfDirectory(
                at: extRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            let locations = preferenceLocations(in: profile)
            let profileName = profile.lastPathComponent

            for idURL in extIDs {
                let id = idURL.lastPathComponent
                let values = try? idURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])
                guard ChromiumExtensionID.isValid(id),
                      values?.isDirectory == true,
                      values?.isSymbolicLink != true
                else { continue }
                let versionNames = ((try? fm.contentsOfDirectory(atPath: idURL.path(percentEncoded: false))) ?? [])
                    .filter { !$0.hasPrefix(".") }
                    .filter { name in
                        var isDir: ObjCBool = false
                        return fm.fileExists(atPath: idURL.appending(path: name).path(percentEncoded: false), isDirectory: &isDir)
                            && isDir.boolValue
                    }
                guard let version = ChromiumVersionFolder.newest(versionNames) else { continue }
                let versionURL = idURL.appending(path: version)
                guard let json = try? Data(contentsOf: versionURL.appending(path: "manifest.json")) else { continue }
                if let record = BrowserExtensionManifest.chromeFamily(
                    json: json,
                    extensionID: id,
                    browser: browser,
                    profile: profileName,
                    path: idURL.path(percentEncoded: false),
                    updatedAt: values?.contentModificationDate,
                    origin: ChromiumPreferences.origin(for: id, location: locations[id], forcedIDs: forced),
                    messages: { locale in
                        try? Data(contentsOf: versionURL.appending(path: "_locales/\(locale)/messages.json"))
                    }
                ) {
                    records.append(record)
                }
            }
        }
        return records
    }

    /// Merges `location` values from Preferences and Secure Preferences
    /// (Chrome on macOS keeps most extension settings in the latter).
    private static func preferenceLocations(in profile: URL) -> [String: Int] {
        var merged: [String: Int] = [:]
        for file in ["Preferences", "Secure Preferences"] {
            guard let data = try? Data(contentsOf: profile.appending(path: file)) else { continue }
            merged.merge(ChromiumPreferences.locations(fromPreferencesJSON: data)) { _, new in new }
        }
        return merged
    }

    /// `ExtensionInstallForcelist` from managed (MDM or configuration
    /// profile) preferences, the usual way adware pins an extension.
    private static func forcedExtensionIDs(for browser: BrowserKind) -> Set<String> {
        let domain: String
        switch browser {
        case .chrome: domain = "com.google.Chrome"
        case .brave: domain = "com.brave.Browser"
        case .edge: domain = "com.microsoft.Edge"
        case .arc: domain = "company.thebrowser.Browser"
        case .safari, .firefox: return []
        }
        let managed = URL(filePath: "/Library/Managed Preferences")
        let candidates = [
            managed.appending(path: "\(domain).plist"),
            managed.appending(path: NSUserName()).appending(path: "\(domain).plist"),
        ]
        var ids = Set<String>()
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }
            ids.formUnion(ChromiumPreferences.forcedIDs(fromPolicyPlist: plist))
        }
        return ids
    }

    // MARK: - Firefox

    private static var firefoxProfilesRoot: URL {
        MCConstants.userAppSupport.appending(path: "Firefox/Profiles")
    }

    private static func firefox() -> [BrowserExtensionRecord] {
        guard let profiles = try? FileManager.default.contentsOfDirectory(
            at: firefoxProfilesRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var records: [BrowserExtensionRecord] = []
        for profile in profiles {
            guard let data = try? Data(contentsOf: profile.appending(path: "extensions.json")) else { continue }
            records.append(contentsOf: BrowserExtensionManifest.firefox(
                json: data,
                profilePath: profile.path(percentEncoded: false)
            ))
        }
        return records
    }

    // MARK: - Safari

    /// Reuses the Extensions module's catalog: Safari app extensions found
    /// inside installed apps, with pluginkit's enabled/disabled overlay.
    private static func safari(pluginKitOutput: String) async -> [BrowserExtensionRecord] {
        var client = ManagedExtensionsClient.live()
        client.pluginKitOutput = { pluginKitOutput }
        let items = await client.load()
        return BrowserExtensionManifest.safari(items) { url in
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
    }
}

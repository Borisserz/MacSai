import AppKit
import Foundation
import MacCleanKit

public struct BrowserExtensionsClient: Sendable {
    public init() {}

    public func list() async -> [BrowserExtensionRecord] {
        await Task.detached {
            var records: [BrowserExtensionRecord] = []
            records.append(contentsOf: Self.chromeFamily(browser: .chrome, relative: "Google/Chrome"))
            records.append(contentsOf: Self.chromeFamily(browser: .brave, relative: "BraveSoftware/Brave-Browser"))
            records.append(contentsOf: Self.chromeFamily(browser: .edge, relative: "Microsoft Edge"))
            records.append(contentsOf: Self.chromeFamily(browser: .arc, relative: "Arc/User Data"))
            records.append(contentsOf: Self.firefox())
            records.append(contentsOf: Self.safari())
            return records.sorted {
                if $0.isMalicious != $1.isMalicious { return $0.isMalicious && !$1.isMalicious }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }.value
    }

    public func applyRemoval(_ record: BrowserExtensionRecord) async -> String? {
        let running = Self.browserIsRunning(record.browser)
        switch BrowserExtensionRemoval.plan(record: record, browserIsRunning: running) {
        case .readOnly:
            if let url = BrowserKind.safari.extensionsPageURL {
                await MainActor.run { NSWorkspace.shared.open(url) }
            }
            return nil
        case .openExtensionsPage(let browser):
            if let url = browser.extensionsPageURL {
                // chrome:// URLs need the browser itself; open the app.
                if let appURL = Self.appURL(for: browser) {
                    await MainActor.run {
                        NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
                    }
                } else {
                    await MainActor.run { NSWorkspace.shared.open(url) }
                }
            }
            return L10n.tr(
                "浏览器正在运行——已打开扩展页面以便你手动移除。",
                "The browser is running — opened its extensions page so you can remove it there.",
                "Браузер запущен — открыта страница расширений, удалите расширение там."
            )
        case .deleteFolder(let path):
            let url = URL(filePath: path)
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
    }

    private static func chromeFamily(browser: BrowserKind, relative: String) -> [BrowserExtensionRecord] {
        let base = MCConstants.userAppSupport.appending(path: relative)
        guard let profiles = try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var records: [BrowserExtensionRecord] = []
        for profile in profiles {
            let extRoot = profile.appending(path: "Extensions")
            guard let extIDs = try? FileManager.default.contentsOfDirectory(
                at: extRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for idURL in extIDs where idURL.hasDirectoryPath {
                let versions = (try? FileManager.default.contentsOfDirectory(
                    at: idURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                guard let versionURL = versions
                    .filter(\.hasDirectoryPath)
                    .sorted(by: {
                        ($0.path as NSString).lastPathComponent
                            > ($1.path as NSString).lastPathComponent
                    })
                    .first
                else { continue }

                let manifestURL = versionURL.appending(path: "manifest.json")
                guard let json = try? Data(contentsOf: manifestURL) else { continue }
                let messages = localizedMessages(in: versionURL)
                let installed = (try? idURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                if let record = BrowserExtensionManifest.chromeFamily(
                    json: json,
                    extensionID: idURL.lastPathComponent,
                    browser: browser,
                    path: idURL.path(percentEncoded: false),
                    installedAt: installed,
                    messagesJSON: messages
                ) {
                    records.append(record)
                }
            }
        }
        return records
    }

    private static func localizedMessages(in versionURL: URL) -> Data? {
        let locales = ["en", "en_US", "en-US", "zh_CN", "ru"]
        for locale in locales {
            let url = versionURL.appending(path: "_locales/\(locale)/messages.json")
            if let data = try? Data(contentsOf: url) { return data }
        }
        return nil
    }

    private static func firefox() -> [BrowserExtensionRecord] {
        let profilesRoot = MCConstants.home.appending(path: "Library/Application Support/Firefox/Profiles")
        guard let profiles = try? FileManager.default.contentsOfDirectory(
            at: profilesRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var records: [BrowserExtensionRecord] = []
        for profile in profiles {
            let jsonURL = profile.appending(path: "extensions.json")
            guard let data = try? Data(contentsOf: jsonURL) else { continue }
            records.append(contentsOf: BrowserExtensionManifest.firefox(
                json: data,
                profilePath: profile.path(percentEncoded: false)
            ))
        }
        return records
    }

    private static func safari() -> [BrowserExtensionRecord] {
        let dir = MCConstants.userLibrary.appending(path: "Safari/Extensions")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let files = contents.map { url in
            let installed = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            return BrowserExtensionManifest.SafariExtensionFile(
                name: url.deletingPathExtension().lastPathComponent,
                path: url.path(percentEncoded: false),
                installedAt: installed
            )
        }
        return BrowserExtensionManifest.safariExtensions(files)
    }

    private static func browserIsRunning(_ browser: BrowserKind) -> Bool {
        let names: [String]
        switch browser {
        case .safari: names = ["Safari"]
        case .chrome: names = ["Google Chrome"]
        case .brave: names = ["Brave Browser"]
        case .edge: names = ["Microsoft Edge"]
        case .arc: names = ["Arc"]
        case .firefox: names = ["firefox", "Firefox"]
        }
        return NSWorkspace.shared.runningApplications.contains { app in
            names.contains(where: { app.localizedName == $0 || app.bundleIdentifier?.contains($0) == true })
        }
    }

    private static func appURL(for browser: BrowserKind) -> URL? {
        let candidates: [String]
        switch browser {
        case .safari: candidates = ["/Applications/Safari.app"]
        case .chrome: candidates = ["/Applications/Google Chrome.app"]
        case .brave: candidates = ["/Applications/Brave Browser.app"]
        case .edge: candidates = ["/Applications/Microsoft Edge.app"]
        case .arc: candidates = ["/Applications/Arc.app"]
        case .firefox: candidates = ["/Applications/Firefox.app"]
        }
        return candidates.map { URL(filePath: $0) }.first {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        }
    }
}

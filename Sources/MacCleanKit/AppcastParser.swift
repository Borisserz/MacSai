import Foundation

/// Minimal Sparkle appcast XML parser. Extracts the latest marketing version's
/// `sparkle:shortVersionString`, falling back to `sparkle:version` only when
/// the feed has no marketing versions.
public final class AppcastParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    /// Keep marketing and build versions in separate domains. A build such as
    /// 4012 must never outrank a marketing version such as 2.1.0.
    private var bestShortVersion: String?
    private var bestShortDownloadURL: URL?
    private var bestBuildVersion: String?
    private var bestBuildDownloadURL: URL?
    private var inItem = false
    private var currentShortVersion: String?
    private var currentShortDownloadURL: URL?
    private var currentBuildVersion: String?
    private var currentBuildDownloadURL: URL?

    public override init() { super.init() }

    public func parseLatestVersion(from data: Data) -> String? {
        parseLatestItem(from: data).version
    }

    public func parseLatestItem(from data: Data) -> (version: String?, downloadURL: URL?) {
        bestShortVersion = nil
        bestShortDownloadURL = nil
        bestBuildVersion = nil
        bestBuildDownloadURL = nil
        inItem = false
        resetCurrentItem()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        let version = UpdateChecker.preferredAppcastVersion(
            shortVersion: bestShortVersion,
            buildVersion: bestBuildVersion
        )
        let downloadURL = bestShortVersion == nil
            ? bestBuildDownloadURL
            : bestShortDownloadURL
        return (version, downloadURL)
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String,
                       namespaceURI: String?, qualifiedName: String?,
                       attributes: [String: String] = [:]) {
        if elementName == "item" {
            inItem = true
            resetCurrentItem()
        }
        if elementName == "enclosure", inItem {
            let downloadURL = attributes["url"].flatMap(URL.init(string:))
            if let shortVersion = attributes["sparkle:shortVersionString"],
               currentShortVersion == nil {
                currentShortVersion = shortVersion
                currentShortDownloadURL = downloadURL
            }
            if let buildVersion = attributes["sparkle:version"],
               currentBuildVersion == nil {
                currentBuildVersion = buildVersion
                currentBuildDownloadURL = downloadURL
            }
        }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String,
                       namespaceURI: String?, qualifiedName: String?) {
        guard elementName == "item" else { return }
        inItem = false
        // Keep the highest version across all items. Sparkle appcasts are NOT
        // guaranteed to list the newest release first (issue #105: taking the
        // first item offered downgrades), so compare every item's version.
        if let version = currentShortVersion,
           shouldReplace(bestShortVersion, with: version) {
            bestShortVersion = version
            bestShortDownloadURL = currentShortDownloadURL
        }
        if let version = currentBuildVersion,
           shouldReplace(bestBuildVersion, with: version) {
            bestBuildVersion = version
            bestBuildDownloadURL = currentBuildDownloadURL
        }
        resetCurrentItem()
    }

    private func shouldReplace(_ bestVersion: String?, with candidate: String) -> Bool {
        guard let bestVersion else { return true }
        return UpdateChecker.isNewer(candidate, than: bestVersion)
    }

    private func resetCurrentItem() {
        currentShortVersion = nil
        currentShortDownloadURL = nil
        currentBuildVersion = nil
        currentBuildDownloadURL = nil
    }
}

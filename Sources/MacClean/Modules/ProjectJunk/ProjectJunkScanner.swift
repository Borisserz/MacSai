import Foundation
import MacCleanKit

/// Walks a user-chosen root and builds `ProjectTreeNode`s for the junk finder.
public struct ProjectJunkScanner: Sendable {
    public init() {}

    public func scan(root: URL, maxDepth: Int = 6) -> [ProjectJunkItem] {
        let nodes = collectNodes(root: root, maxDepth: maxDepth)
        return ProjectJunkFinder.find(nodes: nodes)
    }

    public func asScanResults(_ items: [ProjectJunkItem]) -> [ScanResult] {
        guard !items.isEmpty else { return [] }
        let files = items.map { item in
            FileItem(
                url: URL(filePath: item.path),
                name: (item.path as NSString).lastPathComponent,
                size: item.bytes,
                allocatedSize: item.bytes,
                isDirectory: true
            )
        }
        return [
            ScanResult(
                category: .packageManagerCaches,
                items: files,
                autoSelect: false
            )
        ]
    }

    private func collectNodes(root: URL, maxDepth: Int) -> [ProjectTreeNode] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey, .contentModificationDateKey, .totalFileAllocatedSizeKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var nodes: [ProjectTreeNode] = []
        // Include the root itself so project markers at the top level work.
        if let rootNode = node(for: root, fm: fm) {
            nodes.append(rootNode)
        }

        while let url = enumerator.nextObject() as? URL {
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            if let n = node(for: url, fm: fm) {
                nodes.append(n)
                // Do not descend into regenerable junk — it can be huge.
                let name = url.lastPathComponent
                if ["node_modules", "target", "build", "dist", ".next", "Pods", ".venv", "venv"].contains(name) {
                    enumerator.skipDescendants()
                }
            }
        }
        return nodes
    }

    private func node(for url: URL, fm: FileManager) -> ProjectTreeNode? {
        let path = url.path(percentEncoded: false)
        let children = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey, .totalFileAllocatedSizeKey,
        ])
        let bytes = directoryBytes(url)
        return ProjectTreeNode(
            path: path,
            bytes: bytes,
            modified: values?.contentModificationDate,
            childNames: children
        )
    }

    private func directoryBytes(_ url: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [
                .totalFileAllocatedSizeKey, .isRegularFileKey,
            ])
            if values?.isRegularFile == true {
                total += UInt64(values?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}

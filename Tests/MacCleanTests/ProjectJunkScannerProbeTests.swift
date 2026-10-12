import XCTest
@testable import MacClean

final class ProjectJunkScannerProbeTests: XCTestCase {
    func testScannerFindsJunkOnARealTree() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "pj-probe-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: root) }
        for dir in ["web/node_modules/x", "web/.next", "py/.venv", "api/target/debug", "web/node_modules/.pnpm"] {
            try fm.createDirectory(at: root.appending(path: dir), withIntermediateDirectories: true)
        }
        fm.createFile(atPath: root.appending(path: "web/package.json").path, contents: Data())
        fm.createFile(atPath: root.appending(path: "py/requirements.txt").path, contents: Data())
        fm.createFile(atPath: root.appending(path: "api/Cargo.toml").path, contents: Data())
        fm.createFile(atPath: root.appending(path: "py/.venv/pyvenv.cfg").path, contents: Data())
        fm.createFile(atPath: root.appending(path: "web/node_modules/x/a").path, contents: Data(count: 100_000))
        fm.createFile(atPath: root.appending(path: "web/node_modules/.pnpm/b").path, contents: Data(count: 400_000))

        let items = ProjectJunkScanner().scan(root: root)
        let names = items.map { ($0.path as NSString).lastPathComponent }.sorted()
        print("PROBE found:", items.map { "\($0.path) \($0.bytes)" })
        XCTAssertEqual(names, [".next", ".venv", "node_modules", "target"])
        let nm = items.first { $0.path.hasSuffix("node_modules") || $0.path.hasSuffix("node_modules/") }
        XCTAssertGreaterThanOrEqual(nm?.bytes ?? 0, 500_000, "hidden .pnpm store must be counted")
    }

    func testRefusesSystemAndLibraryRoots() {
        XCTAssertFalse(ProjectJunkScanner.isAllowedRoot(URL(filePath: "/")))
        XCTAssertFalse(ProjectJunkScanner.isAllowedRoot(URL(filePath: "/System/Library")))
        XCTAssertFalse(ProjectJunkScanner.isAllowedRoot(FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")))
        XCTAssertTrue(ProjectJunkScanner.isAllowedRoot(FileManager.default.homeDirectoryForCurrentUser.appending(path: "Code")))
    }
}

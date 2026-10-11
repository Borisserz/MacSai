import XCTest
@testable import MacCleanKit

final class ProjectJunkFinderTests: XCTestCase {
    func testFindsRegenerableFoldersAndNeverTheProjectItself() {
        let root = "/Users/me/Code"
        let nodes = [
            dir("\(root)/web", children: ["package.json", "node_modules", ".next", "dist", "src"]),
            dir("\(root)/web/node_modules", bytes: 500, children: ["left-pad"]),
            dir("\(root)/web/.next", bytes: 80, children: ["cache"]),
            dir("\(root)/web/dist", bytes: 20, children: ["index.js"]),
            dir("\(root)/api", children: ["Cargo.toml", "target", "src"]),
            dir("\(root)/api/target", bytes: 900, children: ["debug"]),
            dir("\(root)/py", children: ["pyproject.toml", ".venv"]),
            dir("\(root)/py/.venv", bytes: 300, children: ["bin"]),
            dir("\(root)/android", children: ["build.gradle", "build"]),
            dir("\(root)/android/build", bytes: 40, children: ["outputs"]),
            dir("\(root)/java", children: ["pom.xml", "target"]),
            dir("\(root)/java/target", bytes: 15, children: ["classes"]),
            dir("\(root)/ios", children: ["Podfile", "Pods"]),
            dir("\(root)/ios/Pods", bytes: 200, children: ["Headers"]),
        ]
        let found = ProjectJunkFinder.find(nodes: nodes)
        let paths = Set(found.map(\.path))
        XCTAssertTrue(paths.contains("\(root)/web/node_modules"))
        XCTAssertTrue(paths.contains("\(root)/web/.next"))
        XCTAssertTrue(paths.contains("\(root)/web/dist"))
        XCTAssertTrue(paths.contains("\(root)/api/target"))
        XCTAssertTrue(paths.contains("\(root)/py/.venv"))
        XCTAssertTrue(paths.contains("\(root)/android/build"))
        XCTAssertTrue(paths.contains("\(root)/java/target"))
        XCTAssertTrue(paths.contains("\(root)/ios/Pods"))
        XCTAssertFalse(paths.contains("\(root)/web"))
        XCTAssertFalse(paths.contains("\(root)/api"))
        XCTAssertEqual(found.first { $0.path.hasSuffix("node_modules") }?.kind, .nodeModules)
        XCTAssertEqual(found.first { $0.path.hasSuffix("/api/target") }?.kind, .rustTarget)
        XCTAssertEqual(found.first { $0.path.hasSuffix("/java/target") }?.kind, .mavenBuild)
        XCTAssertEqual(found.first { $0.path.hasSuffix("/android/build") }?.kind, .gradleBuild)
    }

    func testIgnoresAmbiguousFoldersWithoutAProjectMarker() {
        let nodes = [
            dir("/tmp/notes", children: ["target", "build", "dist", "venv", "Pods"]),
            dir("/tmp/notes/target", bytes: 10, children: []),
            dir("/tmp/notes/build", bytes: 10, children: []),
            dir("/tmp/notes/dist", bytes: 10, children: []),
            dir("/tmp/notes/venv", bytes: 10, children: []),
            dir("/tmp/notes/Pods", bytes: 10, children: []),
        ]
        XCTAssertTrue(ProjectJunkFinder.find(nodes: nodes).isEmpty)
    }

    func testKeepsOnlyTheOutermostJunkDirectory() {
        let nodes = [
            dir("/Code/app", children: ["package.json", "node_modules"]),
            dir("/Code/app/node_modules", bytes: 100, children: ["pkg"]),
            dir("/Code/app/node_modules/pkg", children: ["node_modules"]),
            dir("/Code/app/node_modules/pkg/node_modules", bytes: 5, children: []),
        ]
        let found = ProjectJunkFinder.find(nodes: nodes)
        XCTAssertEqual(found.map(\.path), ["/Code/app/node_modules"])
    }

    func testStaleProjectsSortFirstAndNothingIsPreselected() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 9_000)
        let nodes = [
            dir("/Code/new", modified: newer, children: ["package.json", "node_modules"]),
            dir("/Code/new/node_modules", bytes: 10, children: []),
            dir("/Code/old", modified: older, children: ["package.json", "node_modules"]),
            dir("/Code/old/node_modules", bytes: 1, children: []),
        ]
        let found = ProjectJunkFinder.find(nodes: nodes)
        XCTAssertEqual(found.map(\.projectPath), ["/Code/old", "/Code/new"])
        XCTAssertTrue(ProjectJunkFinder.defaultSelection.isEmpty)
    }

    func testPythonVenvRequiresAPythonMarker() {
        let nodes = [
            dir("/Code/tool", children: ["requirements.txt", "venv"]),
            dir("/Code/tool/venv", bytes: 12, children: ["bin"]),
        ]
        let found = ProjectJunkFinder.find(nodes: nodes)
        XCTAssertEqual(found.map(\.kind), [.pythonVenv])
        XCTAssertEqual(found[0].projectPath, "/Code/tool")
    }

    private func dir(
        _ path: String,
        bytes: UInt64 = 0,
        modified: Date? = nil,
        children: [String]
    ) -> ProjectTreeNode {
        ProjectTreeNode(path: path, bytes: bytes, modified: modified, childNames: children)
    }
}

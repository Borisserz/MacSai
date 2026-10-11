import XCTest
@testable import MacCleanKit

final class DiskHogsTests: XCTestCase {
    func testParsesDockerSystemDF() {
        let text = """
        TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
        Images          12        5         4.2GB     1.8GB (42%)
        Containers      8         2         120MB     80MB (66%)
        Local Volumes   6         1         2.1GB     1.5GB (71%)
        Build Cache     40        0         3.4GB     3.4GB
        """
        let rows = DockerSystemDFParser.parse(text)
        XCTAssertEqual(rows.map(\.category), [.images, .containers, .volumes, .buildCache])
        XCTAssertEqual(rows[0].size, "4.2GB")
        XCTAssertEqual(rows[0].reclaimable, "1.8GB (42%)")
        XCTAssertEqual(rows[3].reclaimable, "3.4GB")
    }

    func testDockerPruneUsesTheCLIAndStartsWithNothingSelected() {
        XCTAssertTrue(DockerPrune.defaultSelection.isEmpty)
        let commands = DockerPrune.arguments(for: [.images, .buildCache])
        XCTAssertEqual(commands, [
            ["image", "prune", "-f"],
            ["builder", "prune", "-f"],
        ])
        XCTAssertEqual(DockerPrune.arguments(for: [.volumes]), [["volume", "prune", "-f"]])
        XCTAssertEqual(DockerPrune.arguments(for: [.containers]), [["container", "prune", "-f"]])
        XCTAssertTrue(DockerPrune.arguments(for: []).isEmpty)
    }

    func testParsesUnavailableSimulatorsAndOldRuntimes() {
        let devices = """
        {"devices":{
          "com.apple.CoreSimulator.SimRuntime.iOS-17-5":[
            {"udid":"AAA","name":"iPhone 15","isAvailable":true},
            {"udid":"BBB","name":"iPhone 14","isAvailable":false}
          ]
        }}
        """.data(using: .utf8)!
        let runtimes = """
        {"runtimes":[
          {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","name":"iOS 18.0","version":"18.0","platform":"iOS","isAvailable":true},
          {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-17-5","name":"iOS 17.5","version":"17.5","platform":"iOS","isAvailable":true},
          {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-16-4","name":"iOS 16.4","version":"16.4","platform":"iOS","isAvailable":false}
        ]}
        """.data(using: .utf8)!
        let devicesFound = SimulatorInventory.parseDevices(devices)
        let runtimesFound = SimulatorInventory.parseRuntimes(runtimes)
        XCTAssertEqual(devicesFound.map(\.udid), ["BBB"])
        XCTAssertEqual(devicesFound[0].name, "iPhone 14")
        XCTAssertEqual(Set(runtimesFound.map(\.identifier)), [
            "com.apple.CoreSimulator.SimRuntime.iOS-17-5",
            "com.apple.CoreSimulator.SimRuntime.iOS-16-4",
        ])
        XCTAssertTrue(runtimesFound.first { $0.identifier.contains("16-4") }?.isAvailable == false)
    }

    func testSimulatorDeleteCommandsAndEmptyDefaultSelection() {
        XCTAssertTrue(SimulatorInventory.defaultSelection.isEmpty)
        XCTAssertEqual(
            SimulatorInventory.deleteArguments(deviceUDID: "BBB"),
            ["simctl", "delete", "BBB"]
        )
        XCTAssertEqual(
            SimulatorInventory.deleteRuntimeArguments(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-16-4"),
            ["simctl", "runtime", "delete", "com.apple.CoreSimulator.SimRuntime.iOS-16-4"]
        )
    }
}

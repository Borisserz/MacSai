import Foundation
import MacCleanKit

/// Runs Docker / xcrun probes used by the Disk Hogs module.
public struct DiskHogsClient: Sendable {
    public init() {}

    public func dockerRows() async -> [DockerDiskRow] {
        guard let docker = MaintenanceTask.resolveDockerPath(existing: {
            FileManager.default.fileExists(atPath: $0)
        }) else { return [] }
        guard let output = try? await run(docker, ["system", "df"]) else { return [] }
        return DockerSystemDFParser.parse(output)
    }

    public func unavailableDevices() async -> [SimulatorDevice] {
        guard let data = try? await runData("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"]) else {
            return []
        }
        return SimulatorInventory.parseDevices(data)
    }

    public func oldRuntimes() async -> [SimulatorRuntime] {
        guard let data = try? await runData("/usr/bin/xcrun", ["simctl", "list", "runtimes", "-j"]) else {
            return []
        }
        return SimulatorInventory.parseRuntimes(data)
    }

    public func pruneDocker(selection: Set<DockerDiskCategory>) async -> String {
        guard let docker = MaintenanceTask.resolveDockerPath(existing: {
            FileManager.default.fileExists(atPath: $0)
        }) else {
            return L10n.tr("未找到 Docker", "Docker not found", "Docker не найден")
        }
        var messages: [String] = []
        for args in DockerPrune.arguments(for: selection) {
            if let out = try? await run(docker, args) {
                messages.append(out.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return messages.joined(separator: "\n")
    }

    public func deleteSimulator(udid: String) async {
        _ = try? await run("/usr/bin/xcrun", SimulatorInventory.deleteArguments(deviceUDID: udid))
    }

    public func deleteRuntime(identifier: String) async {
        _ = try? await run("/usr/bin/xcrun", SimulatorInventory.deleteRuntimeArguments(identifier: identifier))
    }

    private func run(_ command: String, _ args: [String]) async throws -> String {
        let data = try await runData(command, args)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func runData(_ command: String, _ args: [String]) async throws -> Data {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: command)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            return pipe.fileHandleForReading.readDataToEndOfFile()
        }.value
    }
}

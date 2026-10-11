import Foundation

public enum DockerDiskCategory: String, Equatable, Sendable, CaseIterable, Identifiable {
    case images
    case containers
    case volumes
    case buildCache

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .images: L10n.tr("镜像", "Images", "Образы")
        case .containers: L10n.tr("容器", "Containers", "Контейнеры")
        case .volumes: L10n.tr("卷", "Volumes", "Тома")
        case .buildCache: L10n.tr("构建缓存", "Build Cache", "Кэш сборки")
        }
    }
}

public struct DockerDiskRow: Equatable, Sendable, Identifiable {
    public var id: DockerDiskCategory { category }
    public let category: DockerDiskCategory
    public let size: String
    public let reclaimable: String

    public init(category: DockerDiskCategory, size: String, reclaimable: String) {
        self.category = category
        self.size = size
        self.reclaimable = reclaimable
    }
}

public enum DockerSystemDFParser {
    public static func parse(_ text: String) -> [DockerDiskRow] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let columns = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard columns.count >= 5 else { return nil }
            guard let category = category(for: columns[0], second: columns.count > 5 ? columns[1] : nil) else {
                return nil
            }
            // TYPE TOTAL ACTIVE SIZE RECLAIMABLE… — SIZE is always the 4th token
            // after TYPE (which may be two words: "Local Volumes", "Build Cache").
            let typeWordCount = category == .volumes || category == .buildCache ? 2 : 1
            guard columns.count >= typeWordCount + 4 else { return nil }
            let size = columns[typeWordCount + 2]
            let reclaimable = columns.dropFirst(typeWordCount + 3).joined(separator: " ")
            return DockerDiskRow(category: category, size: size, reclaimable: reclaimable)
        }
    }

    private static func category(for first: String, second: String?) -> DockerDiskCategory? {
        switch first.lowercased() {
        case "images": return .images
        case "containers": return .containers
        case "local" where second?.lowercased() == "volumes": return .volumes
        case "build" where second?.lowercased() == "cache": return .buildCache
        default: return nil
        }
    }
}

public enum DockerPrune {
    public static let defaultSelection: Set<DockerDiskCategory> = []

    public static func arguments(for selection: Set<DockerDiskCategory>) -> [[String]] {
        var commands: [[String]] = []
        if selection.contains(.images) { commands.append(["image", "prune", "-f"]) }
        if selection.contains(.containers) { commands.append(["container", "prune", "-f"]) }
        if selection.contains(.volumes) { commands.append(["volume", "prune", "-f"]) }
        if selection.contains(.buildCache) { commands.append(["builder", "prune", "-f"]) }
        return commands
    }
}

public struct SimulatorDevice: Equatable, Sendable, Identifiable {
    public var id: String { udid }
    public let udid: String
    public let name: String
    public let runtime: String

    public init(udid: String, name: String, runtime: String) {
        self.udid = udid
        self.name = name
        self.runtime = runtime
    }
}

public struct SimulatorRuntime: Equatable, Sendable, Identifiable {
    public var id: String { identifier }
    public let identifier: String
    public let name: String
    public let version: String
    public let isAvailable: Bool

    public init(identifier: String, name: String, version: String, isAvailable: Bool) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.isAvailable = isAvailable
    }
}

public enum SimulatorInventory {
    public static let defaultSelection: Set<String> = []

    public static func parseDevices(_ data: Data) -> [SimulatorDevice] {
        struct Payload: Decodable {
            struct Device: Decodable {
                let udid: String
                let name: String
                let isAvailable: Bool
            }
            let devices: [String: [Device]]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }
        return payload.devices.flatMap { runtime, devices in
            devices.compactMap { device in
                guard !device.isAvailable else { return nil }
                return SimulatorDevice(udid: device.udid, name: device.name, runtime: runtime)
            }
        }
    }

    /// Keeps every runtime that is unavailable, plus every available runtime
    /// that is not the newest version on its platform (old runtimes the user
    /// can delete once Xcode has shipped a newer one).
    public static func parseRuntimes(_ data: Data) -> [SimulatorRuntime] {
        struct Payload: Decodable {
            struct Runtime: Decodable {
                let identifier: String
                let name: String
                let version: String
                let platform: String?
                let isAvailable: Bool
            }
            let runtimes: [Runtime]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }
        let mapped = payload.runtimes.map {
            SimulatorRuntime(
                identifier: $0.identifier,
                name: $0.name,
                version: $0.version,
                isAvailable: $0.isAvailable
            )
        }
        let newestByPlatform = Dictionary(
            grouping: payload.runtimes.filter(\.isAvailable),
            by: { $0.platform ?? "unknown" }
        ).mapValues { group in
            group.map(\.version).max(by: isVersionLess) ?? ""
        }
        return mapped.filter { runtime in
            if !runtime.isAvailable { return true }
            let platform = payload.runtimes.first { $0.identifier == runtime.identifier }?.platform ?? "unknown"
            let newest = newestByPlatform[platform] ?? runtime.version
            return isVersionLess(runtime.version, newest)
        }
    }

    public static func deleteArguments(deviceUDID: String) -> [String] {
        ["simctl", "delete", deviceUDID]
    }

    public static func deleteRuntimeArguments(identifier: String) -> [String] {
        ["simctl", "runtime", "delete", identifier]
    }

    private static func isVersionLess(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(left.count, right.count) {
            let l = i < left.count ? left[i] : 0
            let r = i < right.count ? right[i] : 0
            if l != r { return l < r }
        }
        return false
    }
}

import AppKit
import Foundation
import MacCleanKit

/// Result of one privileged `do shell script` invocation.
struct PrivilegedShellResult: Sendable, Equatable {
    let success: Bool
    let output: String
    let error: String?
    let errorNumber: Int?

    static func ok(_ output: String) -> PrivilegedShellResult {
        PrivilegedShellResult(success: true, output: output, error: nil, errorNumber: nil)
    }

    static func failed(_ error: String, errorNumber: Int? = nil) -> PrivilegedShellResult {
        PrivilegedShellResult(success: false, output: "", error: error, errorNumber: errorNumber)
    }
}

/// Runs a pre-quoted shell command line with administrator privileges.
protocol PrivilegedShellRunning: Sendable {
    func run(commandLine: String) async -> PrivilegedShellResult
}

/// In-process AppleScript runner. macOS caches the admin password for about
/// five minutes **per process**, so sequential Maintenance tasks share one
/// prompt instead of asking again for every task (issue #143).
///
/// Calls are serialized on a dedicated queue: `NSAppleScript` is not thread
/// safe, and `executeAndReturnError` can block for minutes (`periodic`) so
/// it must not sit on the Swift concurrency thread pool.
struct AppleScriptPrivilegedRunner: PrivilegedShellRunning {
    private static let queue = DispatchQueue(label: "sai.maintenance.privileged-applescript")

    func run(commandLine: String) async -> PrivilegedShellResult {
        let source = MaintenanceShell.appleScriptSource(commandLine: commandLine)
        return await withCheckedContinuation { continuation in
            Self.queue.async {
                continuation.resume(returning: Self.execute(source))
            }
        }
    }

    private static func execute(_ source: String) -> PrivilegedShellResult {
        guard let script = NSAppleScript(source: source) else {
            return .failed("Failed to create AppleScript")
        }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            let message = (error[NSAppleScript.errorMessage] as? String)
                ?? "AppleScript failed"
            let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
                ?? error[NSAppleScript.errorNumber] as? Int
            return .failed(message, errorNumber: number)
        }
        return .ok(descriptor.stringValue ?? "")
    }
}

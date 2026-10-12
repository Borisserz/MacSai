import Foundation

/// Runs a command with a time budget, terminating it on timeout or when the
/// calling task is cancelled.
///
/// Both pipes are drained while the process runs: waiting for exit before
/// reading deadlocks once output passes the ~64KB pipe buffer, because the
/// child blocks writing while we block waiting.
public enum BoundedProcess {
    public enum Outcome: Equatable, Sendable {
        case exited(status: Int32, stdout: Data, stderr: Data)
        case launchFailed(String)
        case timedOut
        case cancelled
    }

    public static func run(_ executable: String, _ arguments: [String], timeout: Duration) async -> Outcome {
        let handle = Handle()
        do {
            return try await withTimeout(timeout) {
                try await Task.detached { try handle.run(executable, arguments) }.value
            }
        } catch is TimeoutError {
            handle.terminate()
            return .timedOut
        } catch is CancellationError {
            handle.terminate()
            return .cancelled
        } catch {
            return .launchFailed(error.localizedDescription)
        }
    }

    private final class Handle: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var stopped = false

        func run(_ executable: String, _ arguments: [String]) throws -> Outcome {
            let process = Process()
            process.executableURL = URL(filePath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err

            lock.lock()
            if stopped {
                lock.unlock()
                return .cancelled
            }
            do {
                try process.run()
            } catch {
                lock.unlock()
                throw error
            }
            self.process = process
            lock.unlock()

            let stderr = DataBox()
            let group = DispatchGroup()
            DispatchQueue.global(qos: .utility).async(group: group) {
                stderr.data = err.fileHandleForReading.readDataToEndOfFile()
            }
            let stdout = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            group.wait()
            return .exited(status: process.terminationStatus, stdout: stdout, stderr: stderr.data)
        }

        func terminate() {
            lock.lock()
            stopped = true
            let process = self.process
            lock.unlock()
            if let process, process.isRunning { process.terminate() }
        }
    }

    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }
}

public extension BoundedProcess.Outcome {
    var succeeded: Bool {
        if case .exited(0, _, _) = self { return true }
        return false
    }

    var stdoutText: String {
        if case .exited(_, let stdout, _) = self { return String(decoding: stdout, as: UTF8.self) }
        return ""
    }

    var stdoutData: Data {
        if case .exited(_, let stdout, _) = self { return stdout }
        return Data()
    }

    /// First non-empty stderr line (or stdout when stderr is empty), for a
    /// short failure detail. Empty for timeouts and cancellations.
    var failureDetail: String {
        switch self {
        case .exited(_, let stdout, let stderr):
            let text = String(decoding: stderr.isEmpty ? stdout : stderr, as: UTF8.self)
            return text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? ""
        case .launchFailed(let message):
            return message
        case .timedOut, .cancelled:
            return ""
        }
    }
}

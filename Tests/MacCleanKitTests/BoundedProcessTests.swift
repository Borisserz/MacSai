import XCTest
@testable import MacCleanKit

final class BoundedProcessTests: XCTestCase {
    func testCapturesStdoutStderrAndExitStatus() async {
        let outcome = await BoundedProcess.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"], timeout: .seconds(10))
        guard case .exited(let status, let stdout, let stderr) = outcome else {
            return XCTFail("unexpected \(outcome)")
        }
        XCTAssertEqual(status, 3)
        XCTAssertEqual(String(decoding: stdout, as: UTF8.self), "out\n")
        XCTAssertEqual(String(decoding: stderr, as: UTF8.self), "err\n")
        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.failureDetail, "err")
    }

    /// Output larger than the pipe buffer on both streams used to deadlock
    /// when the runner waited for exit before reading.
    func testLargeOutputOnBothStreamsDoesNotDeadlock() async {
        let outcome = await BoundedProcess.run(
            "/bin/sh", ["-c", "head -c 300000 /dev/zero >&2; head -c 300000 /dev/zero"],
            timeout: .seconds(20)
        )
        guard case .exited(0, let stdout, let stderr) = outcome else {
            return XCTFail("unexpected \(outcome)")
        }
        XCTAssertEqual(stdout.count, 300_000)
        XCTAssertEqual(stderr.count, 300_000)
    }

    func testTimeoutTerminatesTheProcess() async {
        let start = ContinuousClock.now
        let outcome = await BoundedProcess.run("/bin/sleep", ["30"], timeout: .milliseconds(300))
        XCTAssertEqual(outcome, .timedOut)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(5))
    }

    func testCancellationTerminatesTheProcess() async {
        let start = ContinuousClock.now
        let task = Task { await BoundedProcess.run("/bin/sleep", ["30"], timeout: .seconds(60)) }
        try? await Task.sleep(for: .milliseconds(300))
        task.cancel()
        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(5))
    }

    func testMissingExecutableIsALaunchFailure() async {
        let outcome = await BoundedProcess.run("/nonexistent/tool", [], timeout: .seconds(5))
        guard case .launchFailed = outcome else { return XCTFail("unexpected \(outcome)") }
    }
}

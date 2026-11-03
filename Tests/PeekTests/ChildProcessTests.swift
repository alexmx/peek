import Foundation
@testable import peek
import Testing

@Suite("ChildProcess Tests")
struct ChildProcessTests {
    private let shell = URL(fileURLWithPath: "/bin/sh")

    @Test
    func returnsTheChildsExitStatus() async {
        #expect(await ChildProcess.run(shell, arguments: ["-c", "exit 0"], timeout: 5) == 0)
        #expect(await ChildProcess.run(shell, arguments: ["-c", "exit 2"], timeout: 5) == 2)
    }

    @Test
    func missingExecutableReturnsNil() async {
        let missing = URL(fileURLWithPath: "/nonexistent/peek-test-binary")
        #expect(await ChildProcess.run(missing, arguments: [], timeout: 5) == nil)
    }

    @Test
    func overdueChildIsStoppedAndReturnsNil() async {
        #expect(await ChildProcess.run(shell, arguments: ["-c", "sleep 30"], timeout: 0.2) == nil)
    }

    @Test
    func childIgnoringSIGTERMIsKilled() async {
        // `trap '' TERM` makes the shell ignore the polite stop; only SIGKILL ends it.
        let started = Date()
        let status = await ChildProcess.run(
            shell,
            arguments: ["-c", "trap '' TERM; while :; do sleep 0.05; done"],
            timeout: 0.2
        )
        #expect(status == nil)
        #expect(Date().timeIntervalSince(started) < 10)
    }
}

@Suite("Screen capture probe")
struct ScreenCaptureProbeTests {
    typealias Probe = PermissionManager.ScreenCaptureProbe

    @Test
    func knownExitStatusesMapToTheirOutcome() {
        #expect(Probe(exitStatus: 0) == .works)
        #expect(Probe(exitStatus: 1) == .inconclusive)
        #expect(Probe(exitStatus: 2) == .denied)
    }

    @Test
    func unknownOrMissingStatusIsInconclusiveNeverDenied() {
        #expect(Probe(exitStatus: 64) == .inconclusive) // e.g. an ArgumentParser usage error
        #expect(Probe(exitStatus: nil) == .inconclusive) // couldn't start, or killed
    }
}

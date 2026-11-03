import Foundation

/// Short-lived helper processes, for work that must not run in peek's own process.
///
/// Screen capture goes through the system's `replayd`, which identifies clients by executable
/// path. Two long-running peek processes from the same binary — MCP servers for two Claude
/// sessions — that have both talked to it knock each other's connection out in a loop:
/// `replayd` spins at ~90% CPU and every capture from that binary hangs until one of them
/// exits. A child process exits before that can start, so window capture and the Screen
/// Recording probe run in one. Never call ScreenCaptureKit or `CGWindowListCreateImage` from
/// peek's own process.
enum ChildProcess {
    /// Grace period between asking an overdue child to stop (SIGTERM) and killing it (SIGKILL).
    private static let killGrace: TimeInterval = 1

    /// Run `executable` and wait for it to exit. Returns its exit status, or nil when it
    /// couldn't start, was killed by a signal, or ran past `timeout` (it's asked to stop then,
    /// and killed after `killGrace` if it ignores that). Its output is discarded.
    static func run(_ executable: URL, arguments: [String], timeout: TimeInterval) async -> Int32? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Stops an overdue child; cancelled the moment the child exits.
        let watchdog = Task {
            try await Delay.seconds(timeout)
            process.terminate()
            try await Delay.seconds(killGrace)
            kill(process.processIdentifier, SIGKILL)
        }
        defer { watchdog.cancel() }
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationReason == .exit ? finished.terminationStatus : nil)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: nil)
            }
        }
    }
}

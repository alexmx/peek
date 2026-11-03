import ArgumentParser

/// Internal: runs the Screen Recording probe and reports the outcome as the exit status, so
/// `PermissionManager.probeScreenCapture` can run it in a child process (see `ChildProcess`).
/// Hidden from help, and deliberately without an MCP tool.
struct ScreenCaptureProbeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: PermissionManager.probeSubcommand,
        abstract: "Probe Screen Recording access (internal)",
        shouldDisplay: false
    )

    func run() async throws {
        throw await ExitCode(PermissionManager.queryScreenCaptureInProcess().rawValue)
    }
}

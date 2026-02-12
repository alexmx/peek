import ArgumentParser
import CoreGraphics

struct WindowTarget: ParsableArguments {
    @Argument(help: "The window ID (omit if using --app or --pid)")
    var windowID: UInt32?

    @Option(name: .long, help: "Target app by name (case-insensitive substring)")
    var app: String?

    @Option(name: .long, help: "Target app by process ID")
    var pid: pid_t?

    /// Resolve the target to a concrete window ID.
    func resolve() throws -> UInt32 {
        if let windowID {
            return windowID
        }
        if let app {
            guard let id = WindowManager.windowID(forApp: app) else {
                throw ValidationError("No window found for app '\(app)'. Run 'peek apps' to see available apps.")
            }
            return id
        }
        if let pid {
            guard let id = WindowManager.windowID(forPID: pid) else {
                throw ValidationError("No window found for PID \(pid). Run 'peek apps' to see available apps.")
            }
            return id
        }
        throw ValidationError("Provide a window ID, --app, or --pid.")
    }
}

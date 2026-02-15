import ArgumentParser
import CoreGraphics

struct WindowTarget: ParsableArguments {
    @Argument(help: "The window ID (omit if using --app or --pid)")
    var windowID: UInt32?

    @Option(name: .long, help: "Target app by name (case-insensitive substring)")
    var app: String?

    @Option(name: .long, help: "Target app by process ID")
    var pid: pid_t?

    struct Resolved {
        let windowID: CGWindowID
        let pid: pid_t
    }

    /// Resolve the target to a concrete window ID and PID from a single ScreenCaptureKit query.
    func resolve() async throws -> Resolved {
        try await Self.resolve(windowID: windowID, app: app, pid: pid)
    }

    /// Core resolution logic shared by CLI commands and MCP tools.
    static func resolve(windowID: UInt32? = nil, app: String? = nil, pid: pid_t? = nil) async throws -> Resolved {
        let windows = try await WindowManager.listWindows()

        if let windowID {
            guard let window = windows.first(where: { $0.windowID == windowID }) else {
                throw ValidationError("No window found with ID \(windowID). Run 'peek apps' to see available windows.")
            }
            return Resolved(windowID: window.windowID, pid: window.pid)
        }
        if let app {
            let matching = windows.filter { $0.ownerName.localizedCaseInsensitiveContains(app) }
            guard let window = matching.first(where: { $0.isOnScreen }) ?? matching.first else {
                throw ValidationError("No window found for app '\(app)'. Run 'peek apps' to see available apps.")
            }
            return Resolved(windowID: window.windowID, pid: window.pid)
        }
        if let pid {
            let matching = windows.filter { $0.pid == pid }
            guard let window = matching.first(where: { $0.isOnScreen }) ?? matching.first else {
                throw ValidationError("No window found for PID \(pid). Run 'peek apps' to see available apps.")
            }
            return Resolved(windowID: window.windowID, pid: window.pid)
        }
        throw ValidationError("Provide a window ID, --app, or --pid.")
    }
}

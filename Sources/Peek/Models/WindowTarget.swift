import AppKit
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
        return try findWindow(in: windows, windowID: windowID, app: app, pid: pid)
    }

    /// Find a window from a list based on search criteria.
    ///
    /// If the targeted app exists but exposes no AXWindow (Dock, Control Center,
    /// Notification Center, window-less menu-bar apps), returns a sentinel
    /// `Resolved(windowID: 0, pid:)` so the caller can scope to the AXApplication
    /// root — see `AccessibilityManager.resolveWindow` for the read side of this
    /// contract. Explicit `windowID` lookups never fall back; only `--app`/`--pid`.
    static func findWindow(
        in windows: [WindowInfo],
        windowID: UInt32? = nil,
        app: String? = nil,
        pid: pid_t? = nil
    ) throws -> Resolved {
        if let windowID {
            guard let window = windows.first(where: { $0.windowID == windowID }) else {
                throw ValidationError("No window found with ID \(windowID). Run 'peek apps' to see available windows.")
            }
            return Resolved(windowID: window.windowID, pid: window.pid)
        }
        if let app {
            let matching = windows.filter { $0.ownerName.localizedCaseInsensitiveContains(app) }
            if let window = matching.first(where: { $0.isOnScreen }) ?? matching.first {
                return Resolved(windowID: window.windowID, pid: window.pid)
            }
            if let runningPID = findRunningPID(byName: app) {
                return Resolved(windowID: 0, pid: runningPID)
            }
            throw ValidationError("No window found for app '\(app)'. Run 'peek apps' to see available apps.")
        }
        if let pid {
            let matching = windows.filter { $0.pid == pid }
            if let window = matching.first(where: { $0.isOnScreen }) ?? matching.first {
                return Resolved(windowID: window.windowID, pid: window.pid)
            }
            if NSRunningApplication(processIdentifier: pid) != nil {
                return Resolved(windowID: 0, pid: pid)
            }
            throw ValidationError("No window found for PID \(pid). Run 'peek apps' to see available apps.")
        }
        throw ValidationError("Provide a window ID, --app, or --pid.")
    }

    /// Look up a running app's PID by case-insensitive name substring. Used to address
    /// window-less apps (Dock, Control Center) by name when SC has nothing to match.
    private static func findRunningPID(byName name: String) -> pid_t? {
        for running in NSWorkspace.shared.runningApplications {
            if running.localizedName?.localizedCaseInsensitiveContains(name) == true {
                return running.processIdentifier
            }
            if running.bundleIdentifier?.localizedCaseInsensitiveContains(name) == true {
                return running.processIdentifier
            }
        }
        return nil
    }
}

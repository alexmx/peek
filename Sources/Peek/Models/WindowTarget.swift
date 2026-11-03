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

    /// Bring the target to the foreground for input commands. See the static version.
    func activate(strict: Bool = true) async throws {
        try await Self.activate(windowID: windowID, app: app, pid: pid, strict: strict)
    }

    /// Activate the target, then verify each point lands on it. See the static version.
    func activateAndGuard(_ points: [(x: Int, y: Int)]) async throws {
        try await Self.activateAndGuard(points, windowID: windowID, app: app, pid: pid)
    }

    /// Bring the target to the foreground before posting input; a no-op without a target
    /// (a raw-coordinate event). A window ID activates the app and requires that window on
    /// top. App/pid alone only activates the app, without policing which of its windows is
    /// on top — a transient popover (search popup, autocomplete) above the main window would
    /// otherwise falsely fail the topmost check.
    ///
    /// `strict: false` makes a failed activation non-fatal. HID keystroke events
    /// (`type`/`key`) post to the OS-frontmost app whether or not peek could *confirm* the
    /// raise, so a strict gate would abort input that would have worked — e.g. a focused
    /// panel field where activation confirmation stalls. Resolution and permission errors
    /// still throw; only `activationFailed` is swallowed. Coordinate gestures stay strict.
    static func activate(windowID: UInt32?, app: String?, pid: pid_t?, strict: Bool = true) async throws {
        guard windowID != nil || app != nil || pid != nil else { return }
        do {
            if windowID != nil {
                let resolved = try await resolve(windowID: windowID, app: app, pid: pid)
                _ = try await InteractionManager.activate(pid: resolved.pid, windowID: resolved.windowID)
            } else {
                _ = try await InteractionManager.activateApp(pid: resolvePID(windowID: nil, app: app, pid: pid))
            }
        } catch PeekError.activationFailed where !strict {
            // Best-effort: proceed to post events to the frontmost app anyway.
        }
    }

    /// For coordinate gestures (click/drag/scroll): activate the target, then verify each
    /// point lands on it — raising an occluded target window, or throwing
    /// `coordinateOffTarget` (see `InteractionManager.ensureOnTarget`). No-op without a target.
    static func activateAndGuard(
        _ points: [(x: Int, y: Int)],
        windowID: UInt32?,
        app: String?,
        pid: pid_t?
    ) async throws {
        guard windowID != nil || app != nil || pid != nil else { return }
        try await activate(windowID: windowID, app: app, pid: pid)
        let targetPID = try await resolvePID(windowID: windowID, app: app, pid: pid)
        try await InteractionManager.ensureOnTarget(points: points, pid: targetPID, windowID: windowID)
    }

    /// Resolve just the target PID, without requiring the app to have a window — for
    /// per-app targets like the menu bar. An explicit window ID still goes through
    /// `resolve`, so an invalid one gets a useful error.
    func resolvePID() async throws -> pid_t {
        try await Self.resolvePID(windowID: windowID, app: app, pid: pid)
    }

    static func resolvePID(windowID: UInt32?, app: String?, pid: pid_t?) async throws -> pid_t {
        if let pid { return pid }
        if let app {
            guard let running = await AppManager.runningApp(named: app) else { throw PeekError.appNotFound(app) }
            return running.pid
        }
        return try await resolve(windowID: windowID).pid
    }

    /// Core resolution logic shared by CLI commands and MCP tools.
    static func resolve(windowID: UInt32? = nil, app: String? = nil, pid: pid_t? = nil) async throws -> Resolved {
        let windows = try await WindowManager.listWindows()
        let runningApps = app == nil ? [] : await AppManager.runningApps()
        do {
            return try findWindow(in: windows, runningApps: runningApps, windowID: windowID, app: app, pid: pid)
        } catch let error as ValidationError {
            // The listing drops non-standard windows (menu-bar panels, status items, small
            // utility windows), but an explicit ID is the caller saying "this window exists" —
            // trust it and look the ID up directly before failing. Capture in particular works
            // on such windows: a MenuBarExtra panel stays capturable by ID even after dismissal.
            if let windowID, let info = WindowManager.windowInfo(byID: windowID) {
                return Resolved(windowID: info.windowID, pid: info.pid)
            }
            throw error
        }
    }

    /// Find a window from a list based on search criteria.
    ///
    /// If the targeted app exists but exposes no AXWindow (Dock, Control Center,
    /// Notification Center, window-less menu-bar apps), returns a sentinel
    /// `Resolved(windowID: 0, pid:)` so the caller can scope to the AXApplication
    /// root — see `AccessibilityManager.resolveWindow` for the read side of this
    /// contract. Explicit `windowID` lookups never fall back to that sentinel; only
    /// `--app`/`--pid`. (`resolve` gives explicit IDs a different fallback: a direct
    /// CGWindowList lookup for windows the filtered listing drops.) `runningApps` is what an
    /// `--app` name falls back to when no window matches.
    static func findWindow(
        in windows: [WindowInfo],
        runningApps: [AppManager.RunningApp] = [],
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
            if let window = frontmostMatch(matching) {
                return Resolved(windowID: window.windowID, pid: window.pid)
            }
            if let running = AppManager.bestMatch(app, in: runningApps) {
                return Resolved(windowID: 0, pid: running.pid)
            }
            throw ValidationError("No window found for app '\(app)'. Run 'peek apps' to see available apps.")
        }
        if let pid {
            let matching = windows.filter { $0.pid == pid }
            if let window = frontmostMatch(matching) {
                return Resolved(windowID: window.windowID, pid: window.pid)
            }
            if NSRunningApplication(processIdentifier: pid) != nil {
                return Resolved(windowID: 0, pid: pid)
            }
            throw ValidationError("No window found for PID \(pid). Run 'peek apps' to see available apps.")
        }
        throw ValidationError("Provide a window ID, --app, or --pid.")
    }

    /// Among windows matching `--app`/`--pid`, pick the frontmost on-screen one — the window
    /// highest in CGWindowList z-order. Activation and keyboard input target the app's key
    /// window, so a multi-window app must resolve to its frontmost window; enumeration order
    /// (SCShareableContent) is unrelated to z-order and unstable across calls, which would
    /// otherwise route input into an arbitrary background window. Falls back to the first
    /// on-screen window, then the first window, if none appear in the z-order list.
    private static func frontmostMatch(_ matching: [WindowInfo]) -> WindowInfo? {
        guard !matching.isEmpty else { return nil }
        let byID = Dictionary(matching.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        for id in WindowManager.onScreenWindowIDsFrontToBack() where byID[id] != nil {
            return byID[id]
        }
        return matching.first(where: { $0.isOnScreen }) ?? matching.first
    }
}

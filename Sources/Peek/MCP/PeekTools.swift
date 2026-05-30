import AppKit
import CoreGraphics
import Foundation
import SwiftMCP

enum PeekTools {
    // MARK: - Helpers

    private static func json(_ value: some Encodable) throws -> MCPToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw PeekError.encodingFailed
        }
        return .text(string)
    }

    private static func resolveWindow(
        windowID: Int?,
        app: String?,
        pid: Int?
    ) async throws -> (windowID: CGWindowID, pid: pid_t) {
        let resolved = try await WindowTarget.resolve(
            windowID: windowID.map { UInt32($0) },
            app: app,
            pid: pid.map { pid_t($0) }
        )
        return (resolved.windowID, resolved.pid)
    }

    /// Resolve just the target PID, without requiring the app to have a window.
    /// Used by tools that only need to touch the menu bar (per-app, not per-window).
    /// Falls back to `resolveWindow` if a `window_id` was explicitly passed so the
    /// caller still gets a useful error if it's invalid.
    private static func resolvePID(windowID: Int?, app: String?, pid: Int?) async throws -> pid_t {
        if let pid {
            return pid_t(pid)
        }
        if let app {
            for running in NSWorkspace.shared.runningApplications
                where running.activationPolicy == .regular
                && running.localizedName?.localizedCaseInsensitiveContains(app) == true {
                return running.processIdentifier
            }
            throw PeekError.appNotFound(app)
        }
        if windowID != nil {
            let (_, p) = try await resolveWindow(windowID: windowID, app: nil, pid: nil)
            return p
        }
        throw PeekError.appNotFound("(no pid, app, or window_id)")
    }

    /// Bring the targeted app to the foreground for tools that post CGEvents
    /// (click, scroll, type). `InteractionManager.activate` blocks until the app
    /// is verified frontmost, so no extra sleep is needed here. If no target was
    /// provided, skip activation entirely — the caller is doing a raw-coordinate
    /// event (e.g. a click on a canvas region with no specific window).
    private static func activateTarget(windowID: Int?, app: String?, pid: Int?) async throws {
        guard windowID != nil || app != nil || pid != nil else { return }
        let (wid, p) = try await resolveWindow(windowID: windowID, app: app, pid: pid)
        _ = try await InteractionManager.activate(pid: p, windowID: wid)
    }

    /// Default tree depth when `args.depth` is not provided. Caps the response size
    /// so a tree from a deeply-nested app (Xcode, System Settings) doesn't blow out
    /// the MCP context window. Callers who need to drill deeper pass an explicit value.
    private static let defaultTreeDepth = 10

    /// Default per-tool wall-clock budget. Synchronous AX/CGEvent calls don't honor
    /// Task cancellation, so if AX itself wedges (e.g. after an interrupted call leaves
    /// an element locked), a tool handler could hang forever and block the MCP server's
    /// stdio pump. This timeout races the handler against a sleep so the server stays
    /// responsive even when AX doesn't.
    private static let defaultTimeout: TimeInterval = 20

    /// Run `body` on a background task and race it against a timeout. If the timeout
    /// fires first, throw `PeekError.timeout`. The underlying AX/CGEvent call may keep
    /// running in the background — there's no way to interrupt the C call — but the
    /// MCP request returns to the client so subsequent tool calls aren't blocked.
    private static func withTimeout<T: Sendable>(
        _ operation: String,
        seconds: TimeInterval = defaultTimeout,
        body: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw PeekError.timeout(operation, seconds)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Argument Types

    struct WindowArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
    }

    struct AppsArgs: MCPToolInput {
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Include off-screen / minimized / other-Space windows (default: false). Off-screen windows aren't interactable without peek_activate, so they're trimmed by default.")
        var include_offscreen: Bool?
    }

    struct TreeArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("Maximum tree depth to traverse (default: 10). Pass a higher value for deeply-nested apps.")
        var depth: Int?
    }

    struct FindArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("Filter by role (exact match, e.g. Button)")
        var role: String?
        @InputProperty("Filter by label — matches AXTitle OR AXDescription, case-insensitive substring. Use this first; buttons often expose their label via description rather than title.")
        var title: String?
        @InputProperty("Filter by value (case-insensitive substring). Display text may be formatted by the app (thousands separators like '1,804', currency symbols, percent signs, locale-specific decimals); use a short partial substring or pre-read the raw value with peek_find rather than guessing the exact string.")
        var value: String?
        @InputProperty("Strict description-only filter (case-insensitive substring). Prefer 'title' for label searches — it already includes description.")
        var desc: String?
        @InputProperty("Hit-test X screen coordinate (use with y instead of filters)")
        var x: Int?
        @InputProperty("Hit-test Y screen coordinate (use with x instead of filters)")
        var y: Int?
    }

    struct ClickArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("X coordinate")
        var x: Int

        @InputProperty("Y coordinate")
        var y: Int
    }

    struct ScrollArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("X coordinate")
        var x: Int
        @InputProperty("Y coordinate")
        var y: Int
        @InputProperty("Vertical scroll amount in pixels. Positive = scroll DOWN (reveal content below), negative = scroll UP")
        var deltaY: Int
        @InputProperty("Horizontal scroll amount in pixels. Positive = scroll RIGHT (reveal content to the right), negative = scroll LEFT")
        var deltaX: Int?
        @InputProperty("Use drag gesture instead of scroll wheel (required for touch-based apps like iOS Simulator)")
        var drag: Bool?
    }

    struct TypeArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("The text to type")
        var text: String
    }

    struct ActionArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty(
            "AX action: Press (buttons), Confirm (text fields), Cancel, ShowMenu, Increment, Decrement, Raise"
        )
        var action: String

        @InputProperty("Filter by role")
        var role: String?
        @InputProperty("Filter by label — matches AXTitle OR AXDescription, case-insensitive substring. Prefer this for label-based searches.")
        var title: String?
        @InputProperty("Filter by value (case-insensitive substring). App-formatted text (thousands separators, currency, percent) may not match a literal — use a short partial substring.")
        var value: String?
        @InputProperty("Strict description-only filter (case-insensitive substring).")
        var desc: String?
        @InputProperty("Perform on all matches (default: first only)")
        var all: Bool?
        @InputProperty("Verification mode after the action. 'none' (default) returns just confirmation. 'tree' captures the post-action accessibility tree (saves a separate peek_tree call). 'diff' snapshots before and after the action and returns only what changed — usually the ideal choice for 'did this control update?' checks (smaller payload than tree, focused on the delta).")
        var verify: String?
        @InputProperty("Tree depth limit for verify=tree or verify=diff (default: full tree).")
        var depth: Int?
        @InputProperty("Seconds to wait between the action and the post-action snapshot for verify=tree/diff (default: 1). Bump for apps that lazy-paint values.")
        var delay: Double?
    }

    struct CaptureArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("Output file path. If omitted, the image is returned inline")
        var output: String?
        @InputProperty(
            "Crop region X offset in window-relative pixels (subtract window frame x from screen coordinate)"
        )
        var x: Int?
        @InputProperty(
            "Crop region Y offset in window-relative pixels (subtract window frame y from screen coordinate)"
        )
        var y: Int?
        @InputProperty("Crop region width")
        var width: Int?
        @InputProperty("Crop region height")
        var height: Int?
    }

    struct MenuArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("Menu item title to click (case-insensitive substring)")
        var click: String?
        @InputProperty(
            "Search for menu items by title (case-insensitive substring) — returns matches with their menu path"
        )
        var find: String?
    }

    struct LaunchArgs: MCPToolInput {
        @InputProperty("Bundle identifier (e.g. com.apple.calculator). Prefer this when known — it's the most reliable resolver.")
        var bundle_id: String?
        @InputProperty("App display name (e.g. 'Calculator'). Searches /Applications, /System/Applications, /System/Applications/Utilities.")
        var name: String?
        @InputProperty("Absolute path to a .app bundle (e.g. /Applications/Notes.app)")
        var path: String?
        @InputProperty("Wait until at least one AX-visible window appears before returning (default: false). Useful when the next call needs a window_id.")
        var wait_for_window: Bool?
    }

    struct QuitArgs: MCPToolInput {
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("Bundle identifier (e.g. com.apple.calculator)")
        var bundle_id: String?
        @InputProperty("App display name (case-insensitive substring; first match wins)")
        var name: String?
        @InputProperty("Force-terminate with forceTerminate() instead of graceful terminate() (default: false). Use only when graceful quit has failed.")
        var force: Bool?
    }

    struct WaitArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("Filter by role (exact match, e.g. Button)")
        var role: String?
        @InputProperty("Filter by label — matches AXTitle OR AXDescription, case-insensitive substring.")
        var title: String?
        @InputProperty("Filter by value (case-insensitive substring). Display text may be formatted by the app (thousands separators like '1,804', currency symbols, percent signs, locale-specific decimals); use a short partial substring or pre-read the raw value with peek_find rather than guessing the exact string.")
        var value: String?
        @InputProperty("Strict description-only filter (case-insensitive substring).")
        var desc: String?
        @InputProperty("Maximum seconds to wait before failing (default: 30)")
        var timeout: Double?
        @InputProperty("Seconds between AX polls (default: 0.5)")
        var poll: Double?
    }

    struct DoctorArgs: MCPToolInput {
        @InputProperty("Prompt for missing permissions via System Settings")
        var prompt: Bool?
    }

    // MARK: - All Tools

    static var all: [MCPTool] {
        [apps, tree, find, click, scroll, type, action, activate, launch, quit, capture, menu, wait, doctor]
    }

    static let apps = MCPTool(
        name: "peek_apps",
        description: "List running macOS applications and their windows with IDs, titles, frames. Use this first to discover available apps and window IDs. Off-screen windows are trimmed by default — pass include_offscreen=true to see hidden / other-Space windows. Always filter by app name when you know it."
    ) { (args: AppsArgs) in
        try await withTimeout("peek_apps") {
            let windows = try await WindowManager.listWindows()
            var entries = AppManager.listApps(windows: windows)
            if let app = args.app {
                entries = entries.filter { $0.name.localizedCaseInsensitiveContains(app) }
            }
            if !(args.include_offscreen ?? false) {
                entries = entries.map { entry in
                    AppEntry(
                        name: entry.name,
                        bundleID: entry.bundleID,
                        pid: entry.pid,
                        isActive: entry.isActive,
                        isHidden: entry.isHidden,
                        windows: entry.windows.filter { $0.isOnScreen }
                    )
                }
            }
            return try json(entries)
        }
    }

    static let tree = MCPTool(
        name: "peek_tree",
        description: "Inspect the accessibility tree of a window. Returns the UI element hierarchy down to a depth limit (default: 10). For deeply-nested apps (Xcode, System Settings), the default keeps the response from blowing out the context; pass a higher 'depth' to drill further. To explore a subtree cheaply, narrow first with peek_find."
    ) { (args: TreeArgs) in
        try await withTimeout("peek_tree") {
            let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
            let depth = args.depth ?? defaultTreeDepth
            let tree = try AccessibilityManager.inspect(pid: pid, windowID: windowID, maxDepth: depth)
            return try json(tree)
        }
    }

    static let find = MCPTool(
        name: "peek_find",
        description: "Search for UI elements (read-only). Start broad with role only, then narrow with title (matches AXTitle OR AXDescription) or value. To interact with found elements, use peek_action directly with the same filters — do NOT use peek_find then peek_click. Best uses: pre-read state to learn what's currently visible (button labels, display values, dialog presence) before peek_wait, peek_click, or peek_action — that way you target labels you've confirmed exist."
    ) { (args: FindArgs) in
        try await withTimeout("peek_find") {
            let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
            if let x = args.x, let y = args.y {
                guard let node = try AccessibilityManager.elementAt(pid: pid, windowID: windowID, x: x, y: y) else {
                    return .text("null")
                }
                return try json(node)
            } else {
                let results = try AccessibilityManager.find(
                    pid: pid, windowID: windowID,
                    role: args.role, title: args.title,
                    value: args.value, description: args.desc
                )
                return try json(results)
            }
        }
    }

    static let click = MCPTool(
        name: "peek_click",
        description: "Low-level click at screen coordinates. Only use for raw coordinate clicks (images, canvas areas) — for UI elements with labels, use peek_action instead, which finds the element and clicks it in one step. Always provide app/pid/window_id to auto-activate the target. Re-read element/window frames via peek_find or peek_apps when a recent peek_activate, peek_action ShowMenu, or menu click could have shifted them — windows commonly move on activation."
    ) { (args: ClickArgs) in
        try await withTimeout("peek_click") {
            try await activateTarget(windowID: args.window_id, app: args.app, pid: args.pid)
            InteractionManager.click(x: Double(args.x), y: Double(args.y))
            return try json(["x": args.x, "y": args.y])
        }
    }

    static let scroll = MCPTool(
        name: "peek_scroll",
        description: "Scroll at screen coordinates. deltaY: use POSITIVE values to scroll DOWN (reveal content below), NEGATIVE to scroll UP. deltaX: positive = right, negative = left. Set drag=true for touch-based apps like iOS Simulator (uses drag gesture instead of scroll wheel). Always provide app/pid/window_id to auto-activate the target app."
    ) { (args: ScrollArgs) in
        try await withTimeout("peek_scroll") {
            try await activateTarget(windowID: args.window_id, app: args.app, pid: args.pid)
            let dx = Int32(clamping: args.deltaX ?? 0)
            let dy = Int32(clamping: args.deltaY)
            if args.drag ?? false {
                InteractionManager.drag(
                    fromX: Double(args.x), fromY: Double(args.y),
                    toX: Double(args.x - Int(dx)), toY: Double(args.y - Int(dy))
                )
            } else {
                InteractionManager.scroll(x: Double(args.x), y: Double(args.y), deltaX: dx, deltaY: dy)
            }
            return try json(["x": args.x, "y": args.y, "deltaX": Int(dx), "deltaY": Int(dy)])
        }
    }

    static let type = MCPTool(
        name: "peek_type",
        description: "Type text via keyboard events to the focused element. Many apps accept typed input directly when their main view is focused — prefer one peek_type call over many peek_action Press calls for any digit/operator/character sequence. If keystrokes need to land in a specific text field, focus it first with peek_click or peek_action; for apps with a global key handler (calculators, games, single-document editors) just call peek_type directly. Passing app/pid/window_id auto-activates the target, so a separate peek_activate is not needed."
    ) { (args: TypeArgs) in
        // Generous budget — `type` posts a key event per character with 10ms gaps.
        try await withTimeout("peek_type", seconds: max(defaultTimeout, Double(args.text.count) * 0.05 + 5)) {
            try await activateTarget(windowID: args.window_id, app: args.app, pid: args.pid)
            InteractionManager.type(text: args.text)
            return try json(["characters": args.text.count])
        }
    }

    static let action = MCPTool(
        name: "peek_action",
        description: "The primary tool for interacting with UI elements. Finds an element by role/title/desc and performs an action on it in one step — no need to peek_find first. Actions: Press (buttons, checkboxes, menu items — works without activating the app), Confirm (text fields), ShowMenu (popups — auto-activates the app), Increment/Decrement (sliders). Set verify='diff' to snapshot before+after and return only what changed — the most efficient way to answer 'did this control update?'. Set verify='tree' to get the full post-action tree instead. Both run after `delay` seconds (default 1s) — bump delay for apps that lazy-paint values."
    ) { (args: ActionArgs) in
        let settleDelay = args.delay ?? 1.0
        return try await withTimeout("peek_action", seconds: defaultTimeout + settleDelay) {
            let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
            let all = args.all ?? false
            let verify = args.verify?.lowercased() ?? "none"

            // For verify=diff we need a snapshot taken BEFORE the action.
            let beforeFlat: [AXNode]? = if verify == "diff" {
                MonitorManager.flattenNodes(
                    try AccessibilityManager.inspect(pid: pid, windowID: windowID, maxDepth: args.depth)
                )
            } else {
                nil
            }

            let nodes: [AXNode] = if all {
                try await InteractionManager.performActionOnAll(
                    pid: pid, windowID: windowID, action: args.action,
                    role: args.role, title: args.title, value: args.value, description: args.desc
                )
            } else {
                try await [InteractionManager.performAction(
                    pid: pid, windowID: windowID, action: args.action,
                    role: args.role, title: args.title, value: args.value, description: args.desc
                )]
            }

            switch verify {
            case "tree":
                try await Task.sleep(nanoseconds: UInt64(settleDelay * 1_000_000_000))
                let tree = try AccessibilityManager.inspect(pid: pid, windowID: windowID, maxDepth: args.depth)
                return try json(ActionTreeResult(action: nodes, resultTree: tree))
            case "diff":
                try await Task.sleep(nanoseconds: UInt64(settleDelay * 1_000_000_000))
                let afterTree = try AccessibilityManager.inspect(pid: pid, windowID: windowID, maxDepth: args.depth)
                let diff = MonitorManager.computeDiff(
                    before: beforeFlat ?? [],
                    after: MonitorManager.flattenNodes(afterTree)
                )
                return try json(ActionDiffResult(action: nodes, diff: diff))
            default:
                return all ? try json(nodes) : try json(nodes[0])
            }
        }
    }

    static let activate = MCPTool(
        name: "peek_activate",
        description: "Bring an app to the foreground and raise its window. Most read-only tools (peek_tree, peek_find, peek_capture, peek_menu --find) and peek_action Press work on backgrounded apps and do NOT auto-activate. Use this when you need to interact with the app's keyboard focus (e.g. before peek_type) or to show UI that requires the app's event loop (popovers, sheets)."
    ) { (args: WindowArgs) in
        try await withTimeout("peek_activate") {
            let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
            let result = try await InteractionManager.activate(pid: pid, windowID: windowID)
            return try json(result)
        }
    }

    static let capture = MCPTool(
        name: "peek_capture",
        description: "Capture a screenshot of a window. Returns the image inline unless an output path is specified. For manual crop, provide x/y/width/height in WINDOW-relative pixels — subtract the window's frame origin (from peek_apps) from screen coordinates returned by peek_tree/peek_find. If capture fails, run peek_doctor: Screen Recording permission is tied to the binary signature and can be revoked after rebuilds even when System Settings shows it as granted."
    ) { (args: CaptureArgs) in
        try await withTimeout("peek_capture") {
            let (windowID, _) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
            let crop: CGRect? = if let x = args.x, let y = args.y,
                                   let w = args.width, let h = args.height {
                CGRect(x: x, y: y, width: w, height: h)
            } else {
                nil
            }

            if let path = args.output {
                let result = try await ScreenCaptureManager.capture(windowID: windowID, outputPath: path, crop: crop)
                return try json(result)
            } else {
                let (data, _, _) = try await ScreenCaptureManager.capturePNGData(windowID: windowID, crop: crop)
                return .content([.image(data: data, mimeType: "image/png")])
            }
        }
    }

    static let menu = MCPTool(
        name: "peek_menu",
        description: "Interact with an app's menu bar. 'find' and the no-argument tree read are read-only and do NOT steal focus. 'find' returns each match with its full path (e.g. 'Edit > Copy') — use it when you're unsure the item exists or need its exact label. If you already know the leaf title (common items like 'Copy', 'Paste', 'Save', 'Quit'), skip find and call click directly. 'click' triggers a menu item and activates the target app first because menus must be visible to execute. Works on apps with no open windows (menus are per-app). Avoid calling with no args — the full menu tree can be very large."
    ) { (args: MenuArgs) in
        try await withTimeout("peek_menu") {
            // The menu bar is per-app, not per-window — resolving a window would
            // wrongly fail for apps that are running but have no windows (Finder
            // with no Finder windows open, background-mode utilities, etc.).
            let pid = try await resolvePID(windowID: args.window_id, app: args.app, pid: args.pid)
            if let clickTitle = args.click {
                // Clicking a menu item needs the menu to actually open — app must be FG.
                _ = try await InteractionManager.activateApp(pid: pid)
                let title = try MenuBarManager.clickMenuItem(pid: pid, title: clickTitle)
                return try json(["title": title])
            } else if let findTitle = args.find {
                // Read-only menu search — works on backgrounded apps via AX.
                let items = try MenuBarManager.findMenuItems(pid: pid, title: findTitle)
                return try json(items)
            } else {
                // Read-only menu tree — same.
                let tree = try MenuBarManager.menuBar(pid: pid)
                return try json(tree)
            }
        }
    }

    static let launch = MCPTool(
        name: "peek_launch",
        description: "Launch a macOS application by bundle_id, name, or absolute path. Pass wait_for_window=true when the next tool call needs a window_id — returns once an AX-visible window appears, errors on 10s timeout. Prefer bundle_id when known. Note: many apps persist view mode, expression, or document state across runs — peek_quit + peek_launch may not reset that. Plan an explicit reset (clear button, mode menu, fresh document) when you need a known starting state."
    ) { (args: LaunchArgs) in
        try await withTimeout("peek_launch", seconds: 15) {
            let url = try AppLifecycleManager.resolveAppURL(
                bundleID: args.bundle_id, name: args.name, path: args.path
            )
            let result = try await AppLifecycleManager.launch(
                url: url, waitForWindow: args.wait_for_window ?? false
            )
            return try json(result)
        }
    }

    static let quit = MCPTool(
        name: "peek_quit",
        description: "Terminate a running application gracefully (force=true uses forceTerminate). Resolve by pid, bundle_id, or name — prefer pid when known. Returns immediately after dispatching the terminate signal; the app's shutdown may continue asynchronously."
    ) { (args: QuitArgs) in
        try await withTimeout("peek_quit") {
            let result = try AppLifecycleManager.quit(
                pid: args.pid.map { pid_t($0) },
                bundleID: args.bundle_id,
                name: args.name,
                force: args.force ?? false
            )
            return try json(result)
        }
    }

    static let wait = MCPTool(
        name: "peek_wait",
        description: "Poll for a UI element to appear, returning as soon as it matches. Use this when you're waiting on a known element (a 'Done' button after a save, a dialog to open, a spinner to vanish) — change you don't directly trigger. For changes you DO trigger, peek_action verify='diff' is more direct. Same filter shape as peek_find. Pre-read state with peek_find first to confirm the label/role you're going to wait for actually appears in this app's UI — waiting on a label that never shows burns the full timeout. Errors with timeout on miss."
    ) { (args: WaitArgs) in
        let timeout = args.timeout ?? 30.0
        let poll = max(args.poll ?? 0.5, 0.1)
        return try await withTimeout("peek_wait", seconds: timeout + defaultTimeout) {
            let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                let results = try AccessibilityManager.find(
                    pid: pid, windowID: windowID,
                    role: args.role, title: args.title,
                    value: args.value, description: args.desc
                )
                if let first = results.first {
                    return try json(first)
                }
                try await Task.sleep(nanoseconds: UInt64(poll * 1_000_000_000))
            }
            throw PeekError.timeout("peek_wait", timeout)
        }
    }

    static let doctor = MCPTool(
        name: "peek_doctor",
        description: "Check if required permissions (Accessibility, Screen Recording) are granted."
    ) { (args: DoctorArgs) in
        let prompt = args.prompt ?? false
        let status = PermissionManager.checkAll(prompt: prompt)
        return try json(status)
    }
}

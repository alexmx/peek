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

    /// Soft-cap on the menu tree response when called without `find`/`path`/`click`.
    /// Big apps (Safari, Xcode) produce 10k+ token dumps that blow up context.
    private static let menuSoftCapBytes = 4000

    private static func cappedMenuTree(_ tree: MenuNode) throws -> MCPToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let full = try encoder.encode(tree)
        if full.count <= menuSoftCapBytes {
            return .text(String(decoding: full, as: UTF8.self))
        }
        let pruned = tree.pruned(toDepth: 1)
        struct Capped: Encodable {
            let tree: MenuNode
            let truncated: Bool
            let hint: String
        }
        return try json(Capped(
            tree: pruned,
            truncated: true,
            hint: "Menu tree exceeded \(menuSoftCapBytes) bytes; only the top-level menu bar items are returned. Re-call peek_menu with `find=<title>` (case-insensitive substring) or `path=<Menu>` / `path=<Menu > Submenu>` to drill in."
        ))
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
    /// (click, scroll, type). If no target was provided, skip activation entirely —
    /// the caller is doing a raw-coordinate event.
    ///
    /// When the caller passes a specific `window_id`, we enforce that THAT window
    /// is topmost (matters for click/scroll at known coordinates). When the caller
    /// only passes app/pid, we just ensure the app is frontmost without policing
    /// which of its windows is on top — otherwise a transient popover (search
    /// popup, autocomplete) sitting above the main window would falsely fail the
    /// topmost check.
    private static func activateTarget(windowID: Int?, app: String?, pid: Int?) async throws {
        guard windowID != nil || app != nil || pid != nil else { return }
        if windowID != nil {
            let (wid, p) = try await resolveWindow(windowID: windowID, app: app, pid: pid)
            _ = try await InteractionManager.activate(pid: p, windowID: wid)
        } else {
            let p = try await resolvePID(windowID: nil, app: app, pid: pid)
            _ = try await InteractionManager.activateApp(pid: p)
        }
    }

    /// Default tree depth when `args.depth` is not provided. Caps the response size
    /// so a tree from a deeply-nested app (Xcode, System Settings) doesn't blow out
    /// the MCP context window. Callers who need to drill deeper pass an explicit value.
    private static let defaultTreeDepth = 5

    /// Default per-tool wall-clock budget. Synchronous AX/CGEvent calls don't honor
    /// Task cancellation, so if AX itself wedges (e.g. after an interrupted call leaves
    /// an element locked), a tool handler could hang forever and block the MCP server's
    /// stdio pump. This timeout races the handler against a sleep so the server stays
    /// responsive even when AX doesn't. 10s covers the realistic worst case for
    /// every tool except peek_launch (15s, fixed) and peek_wait (caller's timeout).
    private static let defaultTimeout: TimeInterval = 10

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
        @InputProperty(
            "Include off-screen / minimized / other-Space windows (default: false; off-screen windows aren't interactable without peek_activate)."
        )
        var include_offscreen: Bool?
    }

    struct TreeArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("Max tree depth (default: 5). Bump to 10+ for deep apps like Xcode or System Settings.")
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
        @InputProperty(
            "Filter by label — matches AXTitle OR AXDescription (case-insensitive substring). If empty, fall back to `value` — some apps (System Settings) store labels in AXStaticText.value."
        )
        var title: String?
        @InputProperty(
            "Filter by value (case-insensitive substring). App formatting (separators, currency, percent) may not match a literal — use a short partial substring or pre-read with peek_find."
        )
        var value: String?
        @InputProperty(
            "Description-only filter (case-insensitive substring). Prefer `title` — it already includes description."
        )
        var desc: String?
        @InputProperty("Filter by enabled state. true = only enabled, false = only disabled. Omit for both.")
        var enabled: Bool?
        @InputProperty("Hit-test X screen coordinate (use with y instead of filters)")
        var x: Int?
        @InputProperty("Hit-test Y screen coordinate (use with x instead of filters)")
        var y: Int?
        @InputProperty("Stop after N matches (1 = first; omit = all). Big speedup on deep trees for existence checks.")
        var limit: Int?
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
        @InputProperty("Click count: 1 (single, default), 2 (double — selects word in text views), 3 (triple — selects line).")
        var count: Int?
    }

    struct DragArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("Source X screen coordinate")
        var from_x: Int
        @InputProperty("Source Y screen coordinate")
        var from_y: Int
        @InputProperty("Destination X screen coordinate")
        var to_x: Int
        @InputProperty("Destination Y screen coordinate")
        var to_y: Int
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
        @InputProperty("Vertical scroll in pixels. Positive = DOWN, negative = UP.")
        var deltaY: Int
        @InputProperty("Horizontal scroll in pixels. Positive = RIGHT, negative = LEFT.")
        var deltaX: Int?
        @InputProperty("Use drag gesture instead of scroll wheel (required for iOS Simulator).")
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
        @InputProperty(
            "Per-character delay in ms (default: 5). Bump to 10-20 if a lazy field drops/duplicates characters."
        )
        var delay_ms: Int?
    }

    struct KeyArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty(
            "Single character ('1', 'a', '/') or named key (escape, tab, return, delete, up/down/left/right, home, end, pageup, pagedown, f1-f12, space)."
        )
        var key: String
        @InputProperty("Modifier keys: any subset of cmd, shift, option, control, fn")
        var modifiers: [String]?
    }

    struct ActionArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("AX action: Press, Confirm, Cancel, ShowMenu, Increment, Decrement, Raise.")
        var action: String

        @InputProperty("Filter by role")
        var role: String?
        @InputProperty(
            "Filter by label — matches AXTitle OR AXDescription (case-insensitive substring). If empty, fall back to `value`."
        )
        var title: String?
        @InputProperty(
            "Filter by value (case-insensitive substring). App-formatted text may not match a literal — use a short partial."
        )
        var value: String?
        @InputProperty("Strict description-only filter (case-insensitive substring).")
        var desc: String?
        @InputProperty("Perform on all matches (default: first only)")
        var all: Bool?
        @InputProperty(
            "Verification: 'none' (default), 'tree' (post-action tree), 'diff' (before+after delta — prefer for 'did this update?')."
        )
        var verify: String?
        @InputProperty("Depth for verify=tree/diff (default: full). Shallow depth can hide deep changes.")
        var depth: Int?
        @InputProperty(
            "Seconds before post-action snapshot for verify=tree/diff (default 0.15). Bump to 0.5+ for lazy-paint apps."
        )
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
        @InputProperty("Crop X offset (window-relative pixels).")
        var x: Int?
        @InputProperty("Crop Y offset (window-relative pixels).")
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
        @InputProperty("Search menu items by title (case-insensitive substring) — returns matches with path.")
        var find: String?
        @InputProperty("Return only the submenu at this path ('Debug' or 'Edit > Find').")
        var path: String?
    }

    struct LaunchArgs: MCPToolInput {
        @InputProperty("Bundle identifier (com.apple.calculator). Most reliable resolver — prefer when known.")
        var bundle_id: String?
        @InputProperty(
            "App display name ('Calculator'). Searches /Applications, /System/Applications, /System/Applications/Utilities."
        )
        var name: String?
        @InputProperty("Absolute path to a .app bundle (/Applications/Notes.app).")
        var path: String?
        @InputProperty(
            "Wait until an AX-visible window appears before returning (default: false). Result includes windowID/windowTitle so you can skip a follow-up peek_apps."
        )
        var wait_for_window: Bool?
    }

    struct QuitArgs: MCPToolInput {
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("Bundle identifier (e.g. com.apple.calculator)")
        var bundle_id: String?
        @InputProperty("App display name (case-insensitive substring; first match wins)")
        var name: String?
        @InputProperty("Force-terminate (default: false). Use only when graceful quit failed.")
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
        @InputProperty(
            "Filter by label — matches AXTitle OR AXDescription (case-insensitive substring). If empty, fall back to `value`."
        )
        var title: String?
        @InputProperty(
            "Filter by value (case-insensitive substring). Use a short partial — app formatting may not match a literal."
        )
        var value: String?
        @InputProperty("Description-only filter (case-insensitive substring).")
        var desc: String?
        @InputProperty("Max seconds to wait (default: 30).")
        var timeout: Double?
        @InputProperty("Seconds between AX polls (default: 0.2, minimum 0.05)")
        var poll: Double?
    }

    struct DoctorArgs: MCPToolInput {
        @InputProperty("Prompt for missing permissions via System Settings")
        var prompt: Bool?
    }

    // MARK: - All Tools

    static var all: [MCPTool] {
        [apps, tree, find, click, drag, scroll, type, key, action, activate, launch, quit, capture, menu, wait, doctor]
    }

    static let apps = MCPTool(
        name: "peek_apps",
        description: "List running apps and their windows with IDs and frames. Pass `app=X` when known — no-arg form lists every running app and is for discovery only. If peek_launch with wait_for_window=true was just called, the windowID/title are in its result — skip this call. Off-screen windows trimmed by default; include_offscreen=true to see them."
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
        description: "Inspect a window's accessibility tree (default depth 5). Prefer peek_find for labeled elements — peek_tree is for learning unfamiliar structure. Bump depth for deeply-nested apps (Xcode, System Settings)."
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
        description: "Search UI elements by role/title/value/description (read-only). Pass limit=1 for existence checks. title matches AXTitle OR AXDescription. Each match is a flat node (no subtree). To interact with a match, call peek_action with the same filters — do NOT peek_find then peek_click. Use to pre-read state before peek_wait/peek_click/peek_action so you target labels that actually exist."
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
                    value: args.value, description: args.desc,
                    enabled: args.enabled, limit: args.limit
                )
                return try json(results)
            }
        }
    }

    static let click = MCPTool(
        name: "peek_click",
        description: "Click at screen coordinates. For labeled elements, use peek_action (finds+clicks in one call). For drag gestures, use peek_drag (two clicks won't synthesize a drag). Pass count=2 for double-click (selects word in text views) or count=3 for triple-click (selects line). Pass app/pid/window_id to auto-activate. Re-read frames after activate/ShowMenu/menu click — windows can move."
    ) { (args: ClickArgs) in
        try await withTimeout("peek_click") {
            try await activateTarget(windowID: args.window_id, app: args.app, pid: args.pid)
            let count = max(1, min(args.count ?? 1, 3))
            InteractionManager.click(x: Double(args.x), y: Double(args.y), count: count)
            return try json(["x": args.x, "y": args.y, "count": count])
        }
    }

    static let drag = MCPTool(
        name: "peek_drag",
        description: "Drag from one screen point to another. Use for drag-reorder, drag-and-drop, marquee selection. Both points are absolute screen coordinates (read from peek_find frames). Pass app/pid/window_id to auto-activate. For touch-style scroll swipes (iOS Simulator), use peek_scroll drag=true instead."
    ) { (args: DragArgs) in
        try await withTimeout("peek_drag") {
            try await activateTarget(windowID: args.window_id, app: args.app, pid: args.pid)
            InteractionManager.drag(
                fromX: Double(args.from_x), fromY: Double(args.from_y),
                toX: Double(args.to_x), toY: Double(args.to_y)
            )
            return try json([
                "from_x": args.from_x, "from_y": args.from_y,
                "to_x": args.to_x, "to_y": args.to_y
            ])
        }
    }

    static let scroll = MCPTool(
        name: "peek_scroll",
        description: "Scroll at screen coordinates. deltaY: positive scrolls DOWN, negative UP. deltaX: positive scrolls RIGHT. Set drag=true for touch-based apps (iOS Simulator) — swipe gesture. For drag-reorder/drag-and-drop, use peek_drag. Pass app/pid/window_id to auto-activate."
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
        description: "Type literal text via keyboard events. Prefer one peek_type over many peek_action Press calls for character/digit sequences. For modifier chords (⌘S, ⇧⌘T) or non-character keys (Esc, Tab, arrows, F-keys), use peek_key. Focus a specific text field first via peek_click/peek_action when needed. Pass app/pid/window_id to auto-activate."
    ) { (args: TypeArgs) in
        let delayMs = UInt32(max(0, args.delay_ms ?? 5))
        let budget = max(defaultTimeout, Double(args.text.count) * Double(delayMs + 5) / 1000.0 + 5)
        return try await withTimeout("peek_type", seconds: budget) {
            try await activateTarget(windowID: args.window_id, app: args.app, pid: args.pid)
            InteractionManager.type(text: args.text, delayMs: delayMs)
            return try json(["characters": args.text.count])
        }
    }

    static let key = MCPTool(
        name: "peek_key",
        description: "Send a single key chord — routes by virtual key code so it triggers app shortcuts (⌘S, ⇧⌘T) or non-character keys (Esc, Tab, arrows, F-keys). Key is a single character or named key (escape, tab, return, delete, up/down/left/right, home, end, pageup, pagedown, f1-f12, space). Modifiers: any of cmd, shift, option, control, fn. Pass app/pid/window_id to auto-activate."
    ) { (args: KeyArgs) in
        try await withTimeout("peek_key") {
            let mods = args.modifiers ?? []
            let flags = try KeyMapping.parseModifiers(mods)
            guard let code = KeyMapping.keyCode(named: args.key) else {
                throw PeekError.invalidArgument(name: "key", value: args.key, valid: KeyMapping.allKeyNames)
            }
            try await activateTarget(windowID: args.window_id, app: args.app, pid: args.pid)
            InteractionManager.sendKey(keyCode: code, flags: flags)
            return try json(["key": args.key, "modifiers": mods.joined(separator: ","), "keyCode": String(code)])
        }
    }

    static let action = MCPTool(
        name: "peek_action",
        description: "Find an element by role/title/desc and act on it in one call. Actions: Press (buttons, checkboxes, items in an ALREADY-OPEN menu — for menu BAR use peek_menu --click), Confirm (text fields), ShowMenu (rare; try Press first and read unsupportedAction errors), Increment/Decrement (sliders). For shortcuts (⌘S, ⌘W, Esc, F-keys), prefer peek_key. Verification: default to verify='diff' for 'did this update?' checks — much smaller than verify='tree'. Bump delay for apps that lazy-paint values."
    ) { (args: ActionArgs) in
        let settleDelay = args.delay ?? 0.15
        return try await withTimeout("peek_action", seconds: defaultTimeout + settleDelay) {
            let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
            let all = args.all ?? false
            let verify = args.verify?.lowercased() ?? "none"

            // verify=tree/diff uses the explicit depth or the full tree — Calculator's
            // display value, for example, lives deeper than peek_tree's small default,
            // and the agent's question is "did this control update?" not "give me a
            // shallow snapshot".
            let beforeFlat: [AXNode]? = if verify == "diff" {
                try MonitorManager.flattenNodes(
                    AccessibilityManager.inspect(pid: pid, windowID: windowID, maxDepth: args.depth)
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
        description: "Bring an app to the foreground and raise its window. Read-only tools (peek_tree/peek_find/peek_capture/peek_menu --find) and peek_action Press work on backgrounded apps — no need to activate first. Use before peek_type or to surface UI that needs the app's event loop (popovers, sheets)."
    ) { (args: WindowArgs) in
        try await withTimeout("peek_activate") {
            let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
            let result = try await InteractionManager.activate(pid: pid, windowID: windowID)
            return try json(result)
        }
    }

    static let capture = MCPTool(
        name: "peek_capture",
        description: "Screenshot a window. Returns image inline unless output path given. Crop x/y/w/h is WINDOW-relative (subtract window frame origin from screen coords). If capture fails, run peek_doctor — Screen Recording permission is binary-signature-bound and can revoke after rebuilds."
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
        description: "Read or click an app's menu bar. Modes: 'find' (read-only, returns matches with paths like 'Edit > Copy'); 'path' (read-only, scoped submenu — 'Debug' or 'Edit > Find'); 'click' (triggers an item, activates the app first). No-arg form truncates on large menus — pass find or path. Items hidden via NSMenuItem.isHidden=true (e.g. Safari's per-tab ⌘1-9) aren't visible to AX — send the shortcut via peek_key."
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
            } else if let scopedPath = args.path {
                // Read-only scoped submenu — avoids dumping the full menu tree.
                let subtree = try MenuBarManager.menuSubtree(pid: pid, path: scopedPath)
                return try json(subtree)
            } else {
                let tree = try MenuBarManager.menuBar(pid: pid)
                return try cappedMenuTree(tree)
            }
        }
    }

    static let launch = MCPTool(
        name: "peek_launch",
        description: "Launch an app by bundle_id, name, or path. Pass wait_for_window=true when the next call needs a window_id — returns once a window appears (windowID/windowTitle in result, skip follow-up peek_apps), errors on 10s timeout. Prefer bundle_id when known. Many apps persist state across launches — plan an explicit reset (clear button, fresh document) when you need a known starting state."
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
        description: "Terminate an app (force=true uses forceTerminate). Resolve by pid (preferred), bundle_id, or name. Returns immediately; shutdown may continue async."
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
        description: "Poll for a UI element to appear (returns at first match). Use for changes you DON'T trigger (Done after save, dialog opens, spinner vanishes). For changes you DO trigger, peek_action verify='diff' is more direct. Same filters as peek_find. Pre-read with peek_find to confirm the label exists — waiting on a missing label burns the full timeout."
    ) { (args: WaitArgs) in
        let timeout = args.timeout ?? 30.0
        let poll = max(args.poll ?? 0.2, 0.05)
        return try await withTimeout("peek_wait", seconds: timeout + defaultTimeout) {
            let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                let results = try AccessibilityManager.find(
                    pid: pid, windowID: windowID,
                    role: args.role, title: args.title,
                    value: args.value, description: args.desc,
                    limit: 1
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

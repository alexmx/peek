import AppKit
import CoreGraphics
import Foundation
import SwiftMCP

enum PeekTools {
    // MARK: - Helpers

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static func json(_ value: some Encodable) throws -> MCPToolResult {
        let data = try jsonEncoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw PeekError.encodingFailed
        }
        return .text(string)
    }

    /// Soft-cap on the menu tree response when called without `find`/`path`/`click`.
    /// Big apps (Safari, Xcode) produce 10k+ token dumps that blow up context.
    private static let menuSoftCapBytes = 4000

    private static func cappedMenuTree(_ tree: MenuNode) throws -> MCPToolResult {
        let full = try jsonEncoder.encode(tree)
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

    /// Resolve just the target PID, without requiring the app to have a window — tools
    /// that only touch the menu bar or the app as a whole. See `WindowTarget.resolvePID`.
    private static func resolvePID(windowID: Int?, app: String?, pid: Int?) async throws -> pid_t {
        try await WindowTarget.resolvePID(windowID: windowID.map { UInt32($0) }, app: app, pid: pid.map { pid_t($0) })
    }

    /// Activate the target before posting input. See `WindowTarget.activate`.
    private static func activateTarget(windowID: Int?, app: String?, pid: Int?, strict: Bool = true) async throws {
        try await WindowTarget.activate(
            windowID: windowID.map { UInt32($0) }, app: app, pid: pid.map { pid_t($0) }, strict: strict
        )
    }

    /// Activate the target, then verify the points land on it. See `WindowTarget.activateAndGuard`.
    private static func activateAndGuard(
        _ points: [(x: Int, y: Int)], windowID: Int?, app: String?, pid: Int?
    ) async throws {
        try await WindowTarget.activateAndGuard(
            points, windowID: windowID.map { UInt32($0) }, app: app, pid: pid.map { pid_t($0) }
        )
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
                try await Delay.seconds(seconds)
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
            "Include non-standard windows — menu-bar panels (MenuBarExtra), status items, small utility windows — and the accessory apps that own them; each window reports its layer (0 = normal, 25 = status item, 101 = menu/panel). A dismissed panel is off-screen yet still capturable by window ID. Noisy without an app filter."
        )
        var include_panels: Bool?
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

    struct TextArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("Filter by role (exact match, e.g. StaticText, TextArea)")
        var role: String?
        @InputProperty("Filter by label — matches AXTitle OR AXDescription (case-insensitive substring)")
        var title: String?
        @InputProperty("Filter by value (case-insensitive substring)")
        var value: String?
        @InputProperty("Description-only filter (case-insensitive substring)")
        var desc: String?
        @InputProperty("Start character offset (default 0)")
        var offset: Int?
        @InputProperty("Max characters to read (default 20000). Page large text by advancing offset.")
        var length: Int?
        @InputProperty(
            "Also return the screen rect (x/y/width/height) of the read range. Pair with a small offset/length to locate a word/phrase, then feed peek_click/peek_drag."
        )
        var bounds: Bool?
        @InputProperty(
            "Also return the element's current caret/selection range {offset, length} (length 0 = caret). Independent of offset/length."
        )
        var selection: Bool?
        @InputProperty(
            "Locate the first occurrence of this exact (case-sensitive) text at or after offset; returns its range as offset + text. Advance offset past a match to page occurrences. Combine with bounds to get its screen rect. Ignores length."
        )
        var substring: String?
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
        @InputProperty(
            "Click count: 1 (single, default), 2 (double — selects word in text views), 3 (triple — selects line)."
        )
        var count: Int?
        @InputProperty(
            "Mouse button: 'left' (default) or 'right'. Right-click opens context menus on canvases / web views."
        )
        var button: String?
        @InputProperty(
            "Modifier keys held during the click: any subset of cmd, shift, option, control, fn. E.g. ['shift'] for range select, ['cmd'] to toggle / open in background."
        )
        var modifiers: [String]?
        @InputProperty(
            "Hold the press this many ms before releasing (long-press; max 5000). ~600 opens iOS context menus and Dock icon menus; much longer puts iOS Home Screen icons into edit mode. With count, holds the last press."
        )
        var hold_ms: Int?
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
        @InputProperty(
            "Hold the press still this many ms before moving (default 100, max 5000). ~500+ is a long-press, which iOS drag-and-drop needs to lift an item."
        )
        var hold_ms: Int?
        @InputProperty("Number of intermediate moves along the path (default 10-40, by distance).")
        var steps: Int?
        @InputProperty("Duration in ms of the move (default 10ms per step); pairs with steps.")
        var duration_ms: Int?
    }

    struct MoveArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("Destination X screen coordinate")
        var x: Int
        @InputProperty("Destination Y screen coordinate")
        var y: Int
        @InputProperty("Smoothed-motion start X. Pair with from_y + steps>1.")
        var from_x: Int?
        @InputProperty("Smoothed-motion start Y. Pair with from_x + steps>1.")
        var from_y: Int?
        @InputProperty(
            "Interpolated moves between (from_x, from_y) and (x, y). Default 1 (single jump); needs from_x/from_y."
        )
        var steps: Int?
        @InputProperty("Sleep after the final move so hover renders. Default 0.")
        var dwell_ms: Int?
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
        @InputProperty(
            "Vertical scroll in points. Positive = DOWN, negative = UP. For a swipe: finger travel in Mac screen points."
        )
        var delta_y: Int
        @InputProperty("Horizontal scroll in points. Positive = RIGHT, negative = LEFT.")
        var delta_x: Int?
        @InputProperty(
            "true = finger swipe, false = scroll wheel. Omit to auto-pick: drag over Xcode Device Hub / Simulator windows (they ignore wheel scrolls), wheel elsewhere."
        )
        var drag: Bool?
        @InputProperty(
            "Spread scroll across N events for smooth animated motion (wheel default 1 = instant jump; swipes are always paced)."
        )
        var steps: Int?
        @InputProperty(
            "Duration in ms of the scroll (wheel: implies smooth; swipe default 300-1000); pairs with steps."
        )
        var duration_ms: Int?
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
        @InputProperty(
            "AX action: Press, Confirm, Cancel, ShowMenu, Increment, Decrement, Raise, Select. Select sets AXSelected — use it for NSOutlineView/NSTableView/source-list rows (which have no Press); match the row's label (it climbs to the selectable row)."
        )
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
        @InputProperty("Crop X offset (window-relative points).")
        var x: Int?
        @InputProperty("Crop Y offset (window-relative points).")
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
        @InputProperty(
            "Menu item to click: title (case-insensitive substring, exact match preferred) or full path as find returns it ('File > Open Recent > Clear Menu'). Use a path when the title appears in several menus."
        )
        var click: String?
        @InputProperty("Search menu items by title (case-insensitive substring) — returns matches with path.")
        var find: String?
        @InputProperty(
            "Return only the submenu at this path ('Debug' or 'Edit > Find'). With click, scopes the click to this submenu."
        )
        var path: String?
        @InputProperty(
            "Operate on the status-item / menu bar extra bar (NSStatusItem, SwiftUI MenuBarExtra) instead of the main menu bar. Combine with find/path to inspect, or click to press a status item (opens its menu — read it with a follow-up extras call)."
        )
        var extras: Bool?
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
        @InputProperty(
            "Paths or URLs to open in the app via application:openURLs:. Collapses launch→menu→file-dialog into one call for document-based apps. Accepts absolute paths, ~/-paths, or URLs (file://, http://, custom schemes)."
        )
        var documents: [String]?
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
        [
            apps,
            tree,
            find,
            text,
            click,
            move,
            drag,
            scroll,
            type,
            key,
            action,
            activate,
            launch,
            quit,
            capture,
            menu,
            wait,
            doctor
        ]
    }

    static let apps = MCPTool(
        name: "peek_apps",
        description: "List running apps and their windows with IDs and frames. Pass `app=X` when known — no-arg form lists every running app and is for discovery only. If peek_launch with wait_for_window=true was just called, the windowID/title are in its result — skip this call. Off-screen windows (minimized, on another Space) are listed too, with isOnScreen=false; peek_activate brings them forward. Menu-bar panels / status items are invisible by default; include_panels=true to list them (e.g. to capture a MenuBarExtra panel by window ID)."
    ) { (args: AppsArgs) in
        try await withTimeout("peek_apps") {
            try await json(AppManager.listApps(named: args.app, includePanels: args.include_panels ?? false))
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
        description: "Search UI elements by role/title/value/description (read-only). Pass limit=1 for existence checks. title matches AXTitle OR AXDescription. Xcode Device Hub windows include the simulated iOS app's elements, with on-screen frames (except upside-down portrait). Each match is a flat node (no subtree). To interact with a match, call peek_action with the same filters — do NOT peek_find then peek_click. Use to pre-read state before peek_wait/peek_click/peek_action so you target labels that actually exist."
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
                    filter: ElementFilter(
                        role: args.role, title: args.title, value: args.value,
                        description: args.desc, enabled: args.enabled
                    ),
                    limit: args.limit
                )
                return try json(results)
            }
        }
    }

    static let text = MCPTool(
        name: "peek_text",
        description: "Read full text content from the first element matching role/title/value/description. Reads parameterized AXStringForRange, so it returns text that peek_find/peek_tree show as empty or truncated (SwiftUI/NavigableStaticText). Returns {length, offset, text, truncated, bounds?, selection?}; page large text by advancing offset. Set bounds=true with a small offset/length to also get the screen rect of that range for peek_click/peek_drag. Set selection=true to also get the live caret/selection range. Pass substring=\"word\" to locate text by content (with bounds for a clickable rect) instead of by offset."
    ) { (args: TextArgs) in
        try await withTimeout("peek_text") {
            let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
            let result = try AccessibilityManager.readText(
                pid: pid, windowID: windowID,
                filter: ElementFilter(role: args.role, title: args.title, value: args.value, description: args.desc),
                offset: args.offset ?? 0, length: args.length,
                bounds: args.bounds ?? false,
                selection: args.selection ?? false,
                substring: args.substring
            )
            return try json(result)
        }
    }

    static let click = MCPTool(
        name: "peek_click",
        description: "Click at screen coordinates. For labeled elements, use peek_action (finds+clicks in one call). For drag gestures, use peek_drag (two clicks won't synthesize a drag). Pass count=2 for double-click (selects word in text views) or count=3 for triple-click (selects line). Pass button='right' for context menus on canvases / web views. Pass modifiers=['shift'|'cmd'|'option'|'control'|'fn'] to hold keys during the click (shift-click = range select, cmd-click = toggle / open in background). Pass hold_ms (~600) for a long-press: iOS context menus in Xcode Device Hub / Simulator, Dock icon menus on the Mac (much longer puts iOS Home Screen icons into edit mode). Pass app/pid/window_id to auto-activate — peek then verifies the point lands on that target (raises an occluded target window, or errors if it's over another window). Re-read frames after activate/ShowMenu/menu click — windows can move."
    ) { (args: ClickArgs) in
        try await withTimeout("peek_click") {
            try await activateAndGuard([(args.x, args.y)], windowID: args.window_id, app: args.app, pid: args.pid)
            let count = max(1, min(args.count ?? 1, 3))
            let buttonRaw = (args.button ?? "left").lowercased()
            guard let button = InteractionManager.MouseButton(rawValue: buttonRaw) else {
                throw PeekError.invalidArgument(name: "button", value: buttonRaw, valid: ["left", "right"])
            }
            let mods = KeyMapping.modifierTokens(args.modifiers ?? [])
            let flags = try KeyMapping.parseModifiers(mods)
            let hold = InteractionManager.clampHoldMs(args.hold_ms ?? 0)
            await InteractionManager.click(
                x: Double(args.x), y: Double(args.y), count: count, button: button, flags: flags,
                holdMs: Double(hold)
            )
            return try json(ClickResult(
                x: args.x, y: args.y, count: count, button: button.rawValue, modifiers: mods,
                holdMs: hold > 0 ? hold : nil
            ))
        }
    }

    static let move = MCPTool(
        name: "peek_move",
        description: "Move the cursor (no click) to drive hover state, tooltips, Dock magnification. Pass from_x/from_y + steps for smoothed motion when an app needs continuous movement. dwell_ms holds the cursor so hover renders. Returns OS-reported cursor position and system-wide AX hit-test under it — use these to verify the hover landed (no follow-up peek_find/peek_capture needed). Pass app/pid/window_id to auto-activate."
    ) { (args: MoveArgs) in
        try await withTimeout("peek_move") {
            try await activateTarget(windowID: args.window_id, app: args.app, pid: args.pid)
            let steps = max(1, args.steps ?? 1)
            let dwell = max(0, args.dwell_ms ?? 0)
            await InteractionManager.move(
                fromX: args.from_x.map(Double.init),
                fromY: args.from_y.map(Double.init),
                toX: Double(args.x),
                toY: Double(args.y),
                steps: steps,
                dwellMs: UInt32(dwell)
            )
            let (cursor, element) = InteractionManager.cursorReadback()
            return try json(MoveResult(
                x: args.x, y: args.y,
                fromX: args.from_x, fromY: args.from_y,
                steps: steps, dwellMs: dwell,
                cursor: cursor, element: element
            ))
        }
    }

    static let drag = MCPTool(
        name: "peek_drag",
        description: "Drag from one screen point to another. Use for drag-reorder, drag-and-drop, marquee selection, window resizing. Pass hold_ms (~500+) to long-press before moving (iOS drag-and-drop needs it to lift an item); steps/duration_ms pace the move (more steps or a longer duration = slower, smoother path). Both points are absolute screen coordinates (read from peek_find frames). Pass app/pid/window_id to auto-activate — peek then verifies the start point lands on that target, raising an occluded target window or erroring if it's over another window (so a background app no longer gets the drag). The end point may be anywhere: a window moved or resized outward, or dropped onto another app. For touch-style scroll swipes (Xcode Device Hub / Simulator), use peek_scroll — it swipes there automatically."
    ) { (args: DragArgs) in
        try await withTimeout("peek_drag") {
            // Only the press point decides what gets dragged; the drop point can be anywhere.
            try await activateAndGuard(
                [(args.from_x, args.from_y)],
                windowID: args.window_id,
                app: args.app,
                pid: args.pid
            )
            await InteractionManager.drag(
                fromX: Double(args.from_x), fromY: Double(args.from_y),
                toX: Double(args.to_x), toY: Double(args.to_y),
                pressHoldMs: Double(InteractionManager.clampHoldMs(
                    args.hold_ms ?? InteractionManager.defaultDragHoldMs
                )),
                steps: args.steps.map { max(1, $0) },
                durationMs: UInt32(max(0, args.duration_ms ?? 0))
            )
            return try json(DragResult(fromX: args.from_x, fromY: args.from_y, toX: args.to_x, toY: args.to_y))
        }
    }

    static let scroll = MCPTool(
        name: "peek_scroll",
        description: "Scroll at screen coordinates. delta_y: positive scrolls DOWN, negative UP. delta_x: positive scrolls RIGHT. Default is an instant jump; set steps>1 (optionally duration_ms) for smooth animated scrolling (total delta unchanged). Over Xcode Device Hub / Simulator windows it swipes like a finger instead (they ignore wheel scrolls); set drag to override. A swipe's delta is finger travel in Mac screen points: the device is drawn scaled down, so its content moves about delta / scale (e.g. ~2x at 0.46x), minus a few points of touch slop. Swipes ease to a stop without momentum. The result's mode says which was used. For drag-reorder/drag-and-drop, use peek_drag. Pass app/pid/window_id to auto-activate — peek then verifies the point lands on that target (raises an occluded target window, or errors if it's over another window)."
    ) { (args: ScrollArgs) in
        try await withTimeout("peek_scroll") {
            try await activateAndGuard([(args.x, args.y)], windowID: args.window_id, app: args.app, pid: args.pid)
            let dx = Int32(clamping: args.delta_x ?? 0)
            let dy = Int32(clamping: args.delta_y)
            let mode: InteractionManager.ScrollMode = args.drag.map { $0 ? .drag : .wheel }
                ?? InteractionManager.defaultScrollMode(x: args.x, y: args.y)
            await InteractionManager.scroll(
                x: args.x, y: args.y,
                deltaX: dx, deltaY: dy,
                mode: mode,
                steps: max(1, args.steps ?? 1),
                durationMs: UInt32(max(0, args.duration_ms ?? 0))
            )
            return try json(ScrollResult(x: args.x, y: args.y, deltaX: Int(dx), deltaY: Int(dy), mode: mode))
        }
    }

    static let type = MCPTool(
        name: "peek_type",
        description: "Type literal text via keyboard events. Prefer one peek_type over many peek_action Press calls for character/digit sequences. For modifier chords (⌘S, ⇧⌘T) or non-character keys (Esc, Tab, arrows, F-keys), use peek_key. Focus a specific text field first via peek_click/peek_action when needed. Pass app/pid/window_id to auto-activate. In Xcode Device Hub, keys reach the iOS device only with its Capture Keyboard checkbox on (peek_action Press)."
    ) { (args: TypeArgs) in
        let delayMs = UInt32(max(0, args.delay_ms ?? 5))
        let budget = max(defaultTimeout, Double(args.text.count) * Double(delayMs + 5) / 1000.0 + 5)
        return try await withTimeout("peek_type", seconds: budget) {
            try await activateTarget(windowID: args.window_id, app: args.app, pid: args.pid, strict: false)
            await InteractionManager.type(text: args.text, delayMs: delayMs)
            return try json(TypeResult(characters: args.text.count))
        }
    }

    static let key = MCPTool(
        name: "peek_key",
        description: "Send a single key chord — routes by virtual key code so it triggers app shortcuts (⌘S, ⇧⌘T) or non-character keys (Esc, Tab, arrows, F-keys). Key is a single character or named key (escape, tab, return, delete, up/down/left/right, home, end, pageup, pagedown, f1-f12, space). Modifiers: any of cmd, shift, option, control, fn. Pass app/pid/window_id to auto-activate. In Xcode Device Hub, keys reach the iOS device only with its Capture Keyboard checkbox on (peek_action Press)."
    ) { (args: KeyArgs) in
        try await withTimeout("peek_key") {
            let mods = KeyMapping.modifierTokens(args.modifiers ?? [])
            let flags = try KeyMapping.parseModifiers(mods)
            guard let code = KeyMapping.keyCode(named: args.key) else {
                throw PeekError.invalidArgument(name: "key", value: args.key, valid: KeyMapping.allKeyNames)
            }
            try await activateTarget(windowID: args.window_id, app: args.app, pid: args.pid, strict: false)
            await InteractionManager.sendKey(keyCode: code, flags: flags)
            return try json(KeyResult(key: args.key, modifiers: mods, keyCode: Int(code)))
        }
    }

    static let action = MCPTool(
        name: "peek_action",
        description: "Find an element by role/title/desc and act on it in one call. Actions: Press (buttons, checkboxes, items in an ALREADY-OPEN menu — for menu BAR use peek_menu --click), Confirm (text fields), ShowMenu (rare; try Press first and read unsupportedAction errors), Increment/Decrement (sliders), Select (rows/items in NSOutlineView/NSTableView/source lists that expose no Press — sets AXSelected; use this instead of coordinate clicks for sidebar/list selection, and verify='diff' to confirm). For shortcuts (⌘S, ⌘W, Esc, F-keys), prefer peek_key. Verification: default to verify='diff' for 'did this update?' checks — much smaller than verify='tree'. Bump delay for apps that lazy-paint values."
    ) { (args: ActionArgs) in
        let settleDelay = args.delay ?? 0.15
        return try await withTimeout("peek_action", seconds: defaultTimeout + settleDelay) {
            let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
            let verifyRaw = args.verify?.lowercased() ?? "none"
            guard let verify = ActionVerifyMode(rawValue: verifyRaw) else {
                throw PeekError.invalidArgument(name: "verify", value: verifyRaw, valid: ["none", "tree", "diff"])
            }
            let outcome = try await InteractionManager.performAndVerify(
                pid: pid, windowID: windowID, action: args.action,
                filter: ElementFilter(role: args.role, title: args.title, value: args.value, description: args.desc),
                all: args.all ?? false, verify: verify, depth: args.depth, settleDelay: settleDelay
            )
            return try json(outcome)
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
        description: "Screenshot a window. Returns image inline unless output path given. Crop x/y/w/h is WINDOW-relative (subtract window frame origin from screen coords). Menu-bar panels (MenuBarExtra): find the window_id via peek_apps include_panels=true and capture by that explicit ID — works even after the panel dismisses (its backing store persists), so no need to race the panel closing. If capture fails, run peek_doctor — Screen Recording permission is binary-signature-bound and can revoke after rebuilds."
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
                let data = try await ScreenCaptureManager.capturePNGData(windowID: windowID, crop: crop)
                return .content([.image(data: data, mimeType: "image/png")])
            }
        }
    }

    static let menu = MCPTool(
        name: "peek_menu",
        description: "Read or click an app's menu bar. Modes: 'find' (read-only, returns matches with paths like 'Edit > Copy'); 'path' (read-only, scoped submenu — 'Debug' or 'Edit > Find'); 'click' (triggers an item, activates the app first; returns the clicked item's full path). Click presses the first enabled match, preferring an exact title — when a title repeats across menus ('Clear Menu' under Apple > Recent Items and File > Open Recent), pass the full path as click or combine click with path. Pass extras=true to target the status-item / menu bar extra bar (NSStatusItem, SwiftUI MenuBarExtra) instead of the main menu — inspect it, or click a status item to open its menu (read the opened menu with a follow-up extras call). No-arg form truncates on large menus — pass find or path. Items hidden via NSMenuItem.isHidden=true (e.g. Safari's per-tab ⌘1-9) aren't visible to AX — send the shortcut via peek_key."
    ) { (args: MenuArgs) in
        try await withTimeout("peek_menu") {
            // The menu bar is per-app, not per-window — resolving a window would
            // wrongly fail for apps that are running but have no windows (Finder
            // with no Finder windows open, background-mode utilities, etc.).
            let pid = try await resolvePID(windowID: args.window_id, app: args.app, pid: args.pid)
            let extras = args.extras ?? false
            if let clickTitle = args.click {
                let clicked = try await MenuBarManager.clickMenuItem(
                    pid: pid, title: clickTitle, path: args.path, extras: extras
                )
                return try json(["title": clicked.title, "path": clicked.path])
            } else if let findTitle = args.find {
                // Read-only menu search — works on backgrounded apps via AX.
                let items = try MenuBarManager.findMenuItems(pid: pid, title: findTitle, extras: extras)
                return try json(items)
            } else if let scopedPath = args.path {
                // Read-only scoped submenu — avoids dumping the full menu tree.
                let subtree = try MenuBarManager.menuSubtree(pid: pid, path: scopedPath, extras: extras)
                return try json(subtree)
            } else {
                let tree = try MenuBarManager.menuBar(pid: pid, extras: extras)
                return try cappedMenuTree(tree)
            }
        }
    }

    static let launch = MCPTool(
        name: "peek_launch",
        description: "Launch an app by bundle_id, name, or path. Pass wait_for_window=true when the next call needs a window_id — returns once a window appears (windowID/windowTitle in result, skip follow-up peek_apps), errors on 10s timeout. Pass documents=[paths/URLs] to open files in the app via application:openURLs: — one deterministic call instead of launch→menu→file-dialog. Prefer bundle_id when known. Many apps persist state across launches — plan an explicit reset (clear button, fresh document) when you need a known starting state."
    ) { (args: LaunchArgs) in
        try await withTimeout("peek_launch", seconds: 15) {
            let url = try AppLifecycleManager.resolveAppURL(
                bundleID: args.bundle_id, name: args.name, path: args.path
            )
            let result = try await AppLifecycleManager.launch(
                url: url, documents: args.documents ?? [], waitForWindow: args.wait_for_window ?? false
            )
            return try json(result)
        }
    }

    static let quit = MCPTool(
        name: "peek_quit",
        description: "Terminate an app (force=true uses forceTerminate). Resolve by pid (preferred), bundle_id, or name. Returns immediately; shutdown may continue async."
    ) { (args: QuitArgs) in
        try await withTimeout("peek_quit") {
            let result = try await AppLifecycleManager.quit(
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
            let filter = ElementFilter(role: args.role, title: args.title, value: args.value, description: args.desc)
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                let results = try AccessibilityManager.find(pid: pid, windowID: windowID, filter: filter, limit: 1)
                if let first = results.first {
                    return try json(first)
                }
                try await Delay.seconds(poll)
            }
            throw PeekError.timeout("peek_wait", timeout)
        }
    }

    static let doctor = MCPTool(
        name: "peek_doctor",
        description: "Check if required permissions (Accessibility, Screen Recording) are granted."
    ) { (args: DoctorArgs) in
        let prompt = args.prompt ?? false
        let status = await PermissionManager.checkAll(prompt: prompt)
        return try json(status)
    }
}

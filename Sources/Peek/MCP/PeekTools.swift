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

    private static func activateIfTargeted(windowID: Int?, app: String?, pid: Int?) async throws {
        guard windowID != nil || app != nil || pid != nil else { return }
        let (wid, p) = try await resolveWindow(windowID: windowID, app: app, pid: pid)
        _ = try InteractionManager.activate(pid: p, windowID: wid)
        usleep(200_000)
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

    struct TreeArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("Maximum tree depth to traverse")
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
        @InputProperty("Filter by title (case-insensitive substring)")
        var title: String?
        @InputProperty("Filter by value (case-insensitive substring)")
        var value: String?
        @InputProperty("Filter by description (case-insensitive substring)")
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
        @InputProperty("Filter by title")
        var title: String?
        @InputProperty("Filter by value")
        var value: String?
        @InputProperty("Filter by description")
        var desc: String?
        @InputProperty("Perform on all matches (default: first only)")
        var all: Bool?
        @InputProperty("Return the accessibility tree after the action (saves a separate peek_tree call)")
        var resultTree: Bool?
        @InputProperty("Tree depth limit when resultTree=true (default: full tree)")
        var depth: Int?
        @InputProperty("Seconds to wait before capturing the tree when resultTree=true (default: 1)")
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

    struct WatchArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("Seconds to wait between snapshots (default: 3)")
        var delay: Double?
    }

    struct DoctorArgs: MCPToolInput {
        @InputProperty("Prompt for missing permissions via System Settings")
        var prompt: Bool?
    }

    // MARK: - All Tools

    static var all: [MCPTool] {
        [apps, tree, find, click, scroll, type, action, activate, capture, menu, watch, doctor]
    }

    static let apps = MCPTool(
        name: "peek_apps",
        description: "List running macOS applications and their windows with IDs, titles, frames. Use this first to discover available apps and window IDs. Always filter by app name when you know it."
    ) { (args: WindowArgs) in
        let windows = try await WindowManager.listWindows()
        var entries = AppManager.listApps(windows: windows)

        if let app = args.app {
            entries = entries.filter { $0.name.localizedCaseInsensitiveContains(app) }
        }

        return try json(entries)
    }

    static let tree = MCPTool(
        name: "peek_tree",
        description: "Inspect the accessibility tree of a window. Returns the full UI element hierarchy. Always use depth to control output size."
    ) { (args: TreeArgs) in
        let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
        let tree = try AccessibilityManager.inspect(pid: pid, windowID: windowID, maxDepth: args.depth)
        return try json(tree)
    }

    static let find = MCPTool(
        name: "peek_find",
        description: "Search for UI elements (read-only). Start broad with role only, then narrow with title/desc. To interact with found elements, use peek_action directly with the same filters — do NOT use peek_find then peek_click."
    ) { (args: FindArgs) in
        let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)

        if let x = args.x, let y = args.y {
            guard let node = try AccessibilityManager.elementAt(pid: pid, windowID: windowID, x: x, y: y) else {
                return .text("No element found at (\(x), \(y)).")
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

    static let click = MCPTool(
        name: "peek_click",
        description: "Low-level click at screen coordinates. Only use for raw coordinate clicks (e.g. on images or canvas areas). For UI elements like buttons, use peek_action instead. Always provide app/pid/window_id to auto-activate the target app."
    ) { (args: ClickArgs) in
        try await activateIfTargeted(windowID: args.window_id, app: args.app, pid: args.pid)
        InteractionManager.click(x: Double(args.x), y: Double(args.y))
        return try json(["x": args.x, "y": args.y])
    }

    static let scroll = MCPTool(
        name: "peek_scroll",
        description: "Scroll at screen coordinates. deltaY: use POSITIVE values to scroll DOWN (reveal content below), NEGATIVE to scroll UP. deltaX: positive = right, negative = left. Set drag=true for touch-based apps like iOS Simulator (uses drag gesture instead of scroll wheel). Always provide app/pid/window_id to auto-activate the target app."
    ) { (args: ScrollArgs) in
        try await activateIfTargeted(windowID: args.window_id, app: args.app, pid: args.pid)
        let dx = Int32(args.deltaX ?? 0)
        let dy = Int32(args.deltaY)
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

    static let type = MCPTool(
        name: "peek_type",
        description: "Type text via keyboard events into the focused element. Always provide app/pid/window_id to auto-activate the target app. Focus a text field first with peek_click or peek_action."
    ) { (args: TypeArgs) in
        try await activateIfTargeted(windowID: args.window_id, app: args.app, pid: args.pid)
        InteractionManager.type(text: args.text)
        return try json(["characters": args.text.count])
    }

    static let action = MCPTool(
        name: "peek_action",
        description: "The primary tool for interacting with UI elements. Finds an element by role/title/desc and performs an action on it in one step — no need to peek_find first. Actions: Press (buttons, checkboxes, menu items), Confirm (text fields), ShowMenu (popups), Increment/Decrement (sliders). Set resultTree=true to also return the post-action accessibility tree (saves a separate peek_tree call)."
    ) { (args: ActionArgs) in
        let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
        let all = args.all ?? false
        let includeTree = args.resultTree ?? false

        let nodes: [AXNode] = if all {
            try InteractionManager.performActionOnAll(
                pid: pid, windowID: windowID, action: args.action,
                role: args.role, title: args.title, value: args.value, description: args.desc
            )
        } else {
            try [InteractionManager.performAction(
                pid: pid, windowID: windowID, action: args.action,
                role: args.role, title: args.title, value: args.value, description: args.desc
            )]
        }

        if includeTree {
            let settleDelay = args.delay ?? 1.0
            usleep(UInt32(settleDelay * 1_000_000))
            let tree = try AccessibilityManager.inspect(pid: pid, windowID: windowID, maxDepth: args.depth)
            return try json(ActionTreeResult(action: nodes, resultTree: tree))
        }

        if all {
            return try json(nodes)
        } else {
            return try json(nodes[0])
        }
    }

    static let activate = MCPTool(
        name: "peek_activate",
        description: "Bring an app to the foreground and raise its window. Rarely needed — most commands (peek_tree, peek_find, peek_action, peek_watch, peek_menu) auto-activate apps."
    ) { (args: WindowArgs) in
        let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
        let result = try InteractionManager.activate(pid: pid, windowID: windowID)
        return try json(result)
    }

    static let capture = MCPTool(
        name: "peek_capture",
        description: "Capture a screenshot of a window. Returns the image inline unless an output path is specified. For manual crop, provide x/y/width/height in window-relative pixels — subtract the window's frame origin (from peek_apps) from screen coordinates (from peek_tree/peek_find)."
    ) { (args: CaptureArgs) in
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

    static let menu = MCPTool(
        name: "peek_menu",
        description: "Interact with an app's menu bar. Use 'find' to search for menu items by title (returns matches with full path). Use 'click' to trigger a menu item. Avoid calling without find/click — the full menu tree can be very large."
    ) { (args: MenuArgs) in
        let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
        _ = try InteractionManager.activate(pid: pid, windowID: windowID)
        if let clickTitle = args.click {
            let title = try MenuBarManager.clickMenuItem(pid: pid, title: clickTitle)
            return try json(["title": title])
        } else if let findTitle = args.find {
            let items = try MenuBarManager.findMenuItems(pid: pid, title: findTitle)
            return try json(items)
        } else {
            let tree = try MenuBarManager.menuBar(pid: pid)
            return try json(tree)
        }
    }

    static let watch = MCPTool(
        name: "peek_watch",
        description: "Monitor async/delayed UI changes by taking two accessibility snapshots separated by a delay (default: 3s) and returning what was added, removed, or changed. Best for: waiting on loading spinners, build progress, animations, or other changes that happen over time. NOT for verifying immediate results of peek_action — use peek_action with resultTree=true or peek_tree instead."
    ) { (args: WatchArgs) in
        let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
        let delay = args.delay ?? 3.0
        let diff = try MonitorManager.diff(pid: pid, windowID: windowID, delay: delay)
        return try json(diff)
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

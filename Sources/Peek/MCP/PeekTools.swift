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
        var pid: Int?    }

    struct TreeArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("Maximum tree depth to traverse")
        var depth: Int?    }

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
        var y: Int?    }

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
        @InputProperty("AX action: Press (buttons), Confirm (text fields), Cancel, ShowMenu, Increment, Decrement, Raise")
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
        var all: Bool?    }

    struct CaptureArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("Output file path (default: window_<id>.png)")
        var output: String?
        @InputProperty("Crop region X offset (window-relative pixels)")
        var x: Int?
        @InputProperty("Crop region Y offset (window-relative pixels)")
        var y: Int?
        @InputProperty("Crop region width")
        var width: Int?
        @InputProperty("Crop region height")
        var height: Int?    }

    struct MenuArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("Menu item title to click (case-insensitive substring)")
        var click: String?
        @InputProperty("Search for menu items by title (case-insensitive substring) — returns matches with their menu path")
        var find: String?    }

    struct WatchArgs: MCPToolInput {
        @InputProperty("Window ID (from peek_apps)")
        var window_id: Int?
        @InputProperty("App name (case-insensitive substring)")
        var app: String?
        @InputProperty("Process ID")
        var pid: Int?
        @InputProperty("Seconds to wait between snapshots (default: 3)")
        var delay: Double?    }

    struct DoctorArgs: MCPToolInput {
        @InputProperty("Prompt for missing permissions via System Settings")
        var prompt: Bool?    }

    // MARK: - All Tools

    static var all: [MCPTool] {
        [apps, tree, find, click, type, action, activate, capture, menu, watch, doctor]
    }

    static let apps = MCPTool(
        name: "peek_apps",
        description: "List running macOS applications and their windows with IDs, titles, frames. Use this first to discover available apps and window IDs."
    ) { (_: WindowArgs) in
        let windows = try await WindowManager.listWindows()
        let entries = AppManager.listApps(windows: windows)
        return try json(entries)
    }

    static let tree = MCPTool(
        name: "peek_tree",
        description: "Inspect the accessibility tree of a window. Returns the full UI element hierarchy."
    ) { (args: TreeArgs) in
        let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
        let tree = try AccessibilityTreeManager.inspect(pid: pid, windowID: windowID, maxDepth: args.depth)
        return try json(tree)
    }

    static let find = MCPTool(
        name: "peek_find",
        description: "Search for UI elements (read-only). Use to discover what's on screen before acting. To interact with found elements, use peek_action directly with the same filters — do NOT use peek_find then peek_click."
    ) { (args: FindArgs) in
        let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)

        if let x = args.x, let y = args.y {
            guard let node = try AccessibilityTreeManager.elementAt(pid: pid, windowID: windowID, x: x, y: y) else {
                return .text("No element found at (\(x), \(y)).")
            }
            return try json(node)
        } else {
            let results = try AccessibilityTreeManager.find(
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
        description: "The primary tool for interacting with UI elements. Finds an element by role/title/desc and performs an action on it in one step — no need to peek_find first. Actions: Press (buttons, checkboxes, menu items), Confirm (text fields), ShowMenu (popups), Increment/Decrement (sliders)."
    ) { (args: ActionArgs) in
        let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
        let all = args.all ?? false

        if all {
            let nodes = try InteractionManager.performActionOnAll(
                pid: pid, windowID: windowID, action: args.action,
                role: args.role, title: args.title, value: args.value, description: args.desc
            )
            return try json(nodes)
        } else {
            let node = try InteractionManager.performAction(
                pid: pid, windowID: windowID, action: args.action,
                role: args.role, title: args.title, value: args.value, description: args.desc
            )
            return try json(node)
        }
    }

    static let activate = MCPTool(
        name: "peek_activate",
        description: "Bring an app to the foreground and raise its window."
    ) { (args: WindowArgs) in
        let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
        let result = try InteractionManager.activate(pid: pid, windowID: windowID)
        return try json(result)
    }

    static let capture = MCPTool(
        name: "peek_capture",
        description: "Capture a screenshot of a window to a PNG file."
    ) { (args: CaptureArgs) in
        let (windowID, _) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
        let path = args.output ?? "window_\(windowID).png"
        let crop: CGRect? = if let x = args.x, let y = args.y,
                               let w = args.width, let h = args.height {
            CGRect(x: x, y: y, width: w, height: h)
        } else {
            nil
        }
        let result = try await ScreenCaptureManager.capture(windowID: windowID, outputPath: path, crop: crop)
        return try json(result)
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
        description: "Detect UI changes in a window. Takes two accessibility snapshots separated by a delay and returns what was added, removed, or changed. Use this to monitor the effect of an action (e.g. build status after triggering a build, UI updates after a click)."
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

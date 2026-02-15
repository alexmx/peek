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

    // MARK: - Shared Schema Fragments

    private static let windowTargetSchema = MCPSchema(properties: [
        "window_id": .integer("Window ID (from peek_apps)"),
        "app": .string("App name (case-insensitive substring)"),
        "pid": .integer("Process ID")
    ])

    // MARK: - Argument Types

    struct WindowArgs: Codable {
        let window_id: Int?
        let app: String?
        let pid: Int?
    }

    struct TreeArgs: Codable {
        let window_id: Int?
        let app: String?
        let pid: Int?
        let depth: Int?
    }

    struct FindArgs: Codable {
        let window_id: Int?
        let app: String?
        let pid: Int?
        let role: String?
        let title: String?
        let value: String?
        let desc: String?
        let x: Int?
        let y: Int?
    }

    struct ClickArgs: Codable {
        let window_id: Int?
        let app: String?
        let pid: Int?
        let x: Int
        let y: Int
    }

    struct TypeArgs: Codable {
        let window_id: Int?
        let app: String?
        let pid: Int?
        let text: String
    }

    struct ActionArgs: Codable {
        let window_id: Int?
        let app: String?
        let pid: Int?
        let action: String
        let role: String?
        let title: String?
        let value: String?
        let desc: String?
        let all: Bool?
    }

    struct CaptureArgs: Codable {
        let window_id: Int?
        let app: String?
        let pid: Int?
        let output: String?
        let x: Int?
        let y: Int?
        let width: Int?
        let height: Int?
    }

    struct MenuArgs: Codable {
        let window_id: Int?
        let app: String?
        let pid: Int?
        let click: String?
        let find: String?
    }

    struct WatchArgs: Codable {
        let window_id: Int?
        let app: String?
        let pid: Int?
        let delay: Double?
    }

    struct DoctorArgs: Codable {
        let prompt: Bool?
    }

    // MARK: - All Tools

    static var all: [MCPTool] {
        [apps, tree, find, click, type, action, activate, capture, menu, watch, doctor]
    }

    static let apps = MCPTool(
        name: "peek_apps",
        description: "List running macOS applications and their windows with IDs, titles, frames. Use this first to discover available apps and window IDs.",
        handler: { (_: WindowArgs) in
            let windows = try await WindowManager.listWindows()
            let entries = AppManager.listApps(windows: windows)
            return try json(entries)
        }
    )

    static let tree = MCPTool(
        name: "peek_tree",
        description: "Inspect the accessibility tree of a window. Returns the full UI element hierarchy.",
        schema: windowTargetSchema.merging(MCPSchema(properties: [
            "depth": .integer("Maximum tree depth to traverse")
        ])),
        handler: { (args: TreeArgs) in
            let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
            let tree = try AccessibilityTreeManager.inspect(pid: pid, windowID: windowID, maxDepth: args.depth)
            return try json(tree)
        }
    )

    static let find = MCPTool(
        name: "peek_find",
        description: "Search for UI elements (read-only). Use to discover what's on screen before acting. To interact with found elements, use peek_action directly with the same filters — do NOT use peek_find then peek_click.",
        schema: windowTargetSchema.merging(MCPSchema(properties: [
            "role": .string("Filter by role (exact match, e.g. Button)"),
            "title": .string("Filter by title (case-insensitive substring)"),
            "value": .string("Filter by value (case-insensitive substring)"),
            "desc": .string("Filter by description (case-insensitive substring)"),
            "x": .integer("Hit-test X screen coordinate (use with y instead of filters)"),
            "y": .integer("Hit-test Y screen coordinate (use with x instead of filters)")
        ])),
        handler: { (args: FindArgs) in
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
    )

    static let click = MCPTool(
        name: "peek_click",
        description: "Low-level click at screen coordinates. Only use for raw coordinate clicks (e.g. on images or canvas areas). For UI elements like buttons, use peek_action instead. Always provide app/pid/window_id to auto-activate the target app.",
        schema: windowTargetSchema.merging(MCPSchema(
            properties: [
                "x": .integer("X coordinate"),
                "y": .integer("Y coordinate")
            ],
            required: ["x", "y"]
        )),
        handler: { (args: ClickArgs) in
            try await activateIfTargeted(windowID: args.window_id, app: args.app, pid: args.pid)
            InteractionManager.click(x: Double(args.x), y: Double(args.y))
            return try json(["x": args.x, "y": args.y])
        }
    )

    static let type = MCPTool(
        name: "peek_type",
        description: "Type text via keyboard events into the focused element. Always provide app/pid/window_id to auto-activate the target app. Focus a text field first with peek_click or peek_action.",
        schema: windowTargetSchema.merging(MCPSchema(
            properties: ["text": .string("The text to type")],
            required: ["text"]
        )),
        handler: { (args: TypeArgs) in
            try await activateIfTargeted(windowID: args.window_id, app: args.app, pid: args.pid)
            InteractionManager.type(text: args.text)
            return try json(["characters": args.text.count])
        }
    )

    static let action = MCPTool(
        name: "peek_action",
        description: "The primary tool for interacting with UI elements. Finds an element by role/title/desc and performs an action on it in one step — no need to peek_find first. Actions: Press (buttons, checkboxes, menu items), Confirm (text fields), ShowMenu (popups), Increment/Decrement (sliders).",
        schema: windowTargetSchema.merging(MCPSchema(
            properties: [
                "action": .string(
                    "AX action: Press (buttons), Confirm (text fields), Cancel, ShowMenu, Increment, Decrement, Raise"
                ),
                "role": .string("Filter by role"),
                "title": .string("Filter by title"),
                "value": .string("Filter by value"),
                "desc": .string("Filter by description"),
                "all": .boolean("Perform on all matches (default: first only)")
            ],
            required: ["action"]
        )),
        handler: { (args: ActionArgs) in
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
    )

    static let activate = MCPTool(
        name: "peek_activate",
        description: "Bring an app to the foreground and raise its window.",
        schema: windowTargetSchema,
        handler: { (args: WindowArgs) in
            let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
            let result = try InteractionManager.activate(pid: pid, windowID: windowID)
            return try json(result)
        }
    )

    static let capture = MCPTool(
        name: "peek_capture",
        description: "Capture a screenshot of a window to a PNG file.",
        schema: windowTargetSchema.merging(MCPSchema(properties: [
            "output": .string("Output file path (default: window_<id>.png)"),
            "x": .integer("Crop region X offset (window-relative pixels)"),
            "y": .integer("Crop region Y offset (window-relative pixels)"),
            "width": .integer("Crop region width"),
            "height": .integer("Crop region height")
        ])),
        handler: { (args: CaptureArgs) in
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
    )

    static let menu = MCPTool(
        name: "peek_menu",
        description: "Interact with an app's menu bar. Use 'find' to search for menu items by title (returns matches with full path). Use 'click' to trigger a menu item. Avoid calling without find/click — the full menu tree can be very large.",
        schema: windowTargetSchema.merging(MCPSchema(properties: [
            "click": .string("Menu item title to click (case-insensitive substring)"),
            "find": .string(
                "Search for menu items by title (case-insensitive substring) — returns matches with their menu path"
            )
        ])),
        handler: { (args: MenuArgs) in
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
    )

    static let watch = MCPTool(
        name: "peek_watch",
        description: "Detect UI changes in a window. Takes two accessibility snapshots separated by a delay and returns what was added, removed, or changed. Use this to monitor the effect of an action (e.g. build status after triggering a build, UI updates after a click).",
        schema: windowTargetSchema.merging(MCPSchema(properties: [
            "delay": .number("Seconds to wait between snapshots (default: 3)")
        ])),
        handler: { (args: WatchArgs) in
            let (windowID, pid) = try await resolveWindow(windowID: args.window_id, app: args.app, pid: args.pid)
            let delay = args.delay ?? 3.0
            let diff = try MonitorManager.diff(pid: pid, windowID: windowID, delay: delay)
            return try json(diff)
        }
    )

    static let doctor = MCPTool(
        name: "peek_doctor",
        description: "Check if required permissions (Accessibility, Screen Recording) are granted.",
        schema: MCPSchema(properties: [
            "prompt": .boolean("Prompt for missing permissions via System Settings")
        ]),
        handler: { (args: DoctorArgs) in
            let prompt = args.prompt ?? false
            let status = PermissionManager.checkAll(prompt: prompt)
            return try json(status)
        }
    )
}

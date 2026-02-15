import CoreGraphics
import Foundation
import SwiftCliMcp

enum PeekTools {
    // MARK: - Helpers

    private static func jsonString(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw PeekError.encodingFailed
        }
        return json
    }

    private static func resolveWindow(from args: [String: Any]) async throws -> (windowID: CGWindowID, pid: pid_t) {
        let resolved = try await WindowTarget.resolve(
            windowID: (args["window_id"] as? Int).map { UInt32($0) },
            app: args["app"] as? String,
            pid: (args["pid"] as? Int).map { pid_t($0) }
        )
        return (resolved.windowID, resolved.pid)
    }

    /// Activate the target app if window targeting args are provided.
    /// Used by click/type which operate at screen level and need the window in foreground.
    private static func activateIfTargeted(_ args: [String: Any]) async throws {
        guard args["window_id"] != nil || args["app"] != nil || args["pid"] != nil else { return }
        let (windowID, pid) = try await resolveWindow(from: args)
        _ = try InteractionManager.activate(pid: pid, windowID: windowID)
    }

    // MARK: - Shared Schema Fragments

    private static let windowTargetSchema = MCPSchema(properties: [
        "window_id": .integer("Window ID (from peek_apps)"),
        "app": .string("App name (case-insensitive substring)"),
        "pid": .integer("Process ID"),
    ])

    // MARK: - All Tools

    static var all: [MCPTool] {
        [apps, window, find, click, type, action, activate, capture, menu, doctor]
    }

    static let apps = MCPTool(
        name: "peek_apps",
        description: "List running macOS applications and their windows with IDs, titles, frames"
    ) { _ in
        let windows = try await WindowManager.listWindows()
        let entries = AppManager.listApps(windows: windows)
        return try jsonString(entries)
    }

    static let window = MCPTool(
        name: "peek_tree",
        description: "Inspect the accessibility tree of a window. Returns the full UI element hierarchy.",
        schema: windowTargetSchema.merging(MCPSchema(properties: [
            "depth": .integer("Maximum tree depth to traverse"),
        ]))
    ) { args in
        let (windowID, pid) = try await resolveWindow(from: args)
        let depth = args["depth"] as? Int
        let tree = try AccessibilityTreeManager.inspect(pid: pid, windowID: windowID, maxDepth: depth)
        return try jsonString(tree)
    }

    static let find = MCPTool(
        name: "peek_find",
        description: "Search for UI elements by attributes or coordinates. Use role/title/value/desc for attribute search, or x/y for hit-test.",
        schema: windowTargetSchema.merging(MCPSchema(properties: [
            "role": .string("Filter by role (exact match, e.g. Button)"),
            "title": .string("Filter by title (case-insensitive substring)"),
            "value": .string("Filter by value (case-insensitive substring)"),
            "desc": .string("Filter by description (case-insensitive substring)"),
            "x": .integer("Hit-test X screen coordinate (use with y instead of filters)"),
            "y": .integer("Hit-test Y screen coordinate (use with x instead of filters)"),
        ]))
    ) { args in
        let (windowID, pid) = try await resolveWindow(from: args)

        if let x = args["x"] as? Int, let y = args["y"] as? Int {
            guard let node = try AccessibilityTreeManager.elementAt(pid: pid, windowID: windowID, x: x, y: y) else {
                return "No element found at (\(x), \(y))."
            }
            return try jsonString(node)
        } else {
            let results = try AccessibilityTreeManager.find(
                pid: pid, windowID: windowID,
                role: args["role"] as? String,
                title: args["title"] as? String,
                value: args["value"] as? String,
                description: args["desc"] as? String
            )
            return try jsonString(results)
        }
    }

    static let click = MCPTool(
        name: "peek_click",
        description: "Click at screen coordinates. Requires the app to be in the foreground — always provide app/pid/window_id to auto-activate. Prefer peek_action for clicking UI elements like buttons.",
        schema: windowTargetSchema.merging(MCPSchema(
            properties: [
                "x": .integer("X coordinate"),
                "y": .integer("Y coordinate"),
            ],
            required: ["x", "y"]
        ))
    ) { args in
        guard let x = args["x"] as? Int, let y = args["y"] as? Int else {
            throw PeekError.elementNotFound
        }
        try await activateIfTargeted(args)
        InteractionManager.click(x: Double(x), y: Double(y))
        return try jsonString(["x": x, "y": y])
    }

    static let type = MCPTool(
        name: "peek_type",
        description: "Type text via keyboard events. Requires the app to be in the foreground — always provide app/pid/window_id to auto-activate.",
        schema: windowTargetSchema.merging(MCPSchema(
            properties: ["text": .string("The text to type")],
            required: ["text"]
        ))
    ) { args in
        guard let text = args["text"] as? String else {
            throw PeekError.elementNotFound
        }
        try await activateIfTargeted(args)
        InteractionManager.type(text: text)
        return try jsonString(["characters": text.count])
    }

    static let action = MCPTool(
        name: "peek_action",
        description: "Perform an accessibility action on a UI element matching the given filters. Preferred over peek_click for interacting with UI elements — finds and acts on elements by role/title/desc without needing coordinates. Common actions by role: Button/MenuItem→Press, TextField/TextArea→Confirm (or use peek_click to focus), CheckBox→Press, Slider→Increment/Decrement.",
        schema: windowTargetSchema.merging(MCPSchema(
            properties: [
                "action": .string("AX action: Press (buttons), Confirm (text fields), Cancel, ShowMenu, Increment, Decrement, Raise"),
                "role": .string("Filter by role"),
                "title": .string("Filter by title"),
                "value": .string("Filter by value"),
                "desc": .string("Filter by description"),
                "all": .boolean("Perform on all matches (default: first only)"),
            ],
            required: ["action"]
        ))
    ) { args in
        let (windowID, pid) = try await resolveWindow(from: args)
        guard let actionName = args["action"] as? String else {
            throw PeekError.elementNotFound
        }
        let role = args["role"] as? String
        let title = args["title"] as? String
        let value = args["value"] as? String
        let desc = args["desc"] as? String
        let all = args["all"] as? Bool ?? false

        if all {
            let nodes = try InteractionManager.performActionOnAll(
                pid: pid, windowID: windowID, action: actionName,
                role: role, title: title, value: value, description: desc
            )
            return try jsonString(nodes)
        } else {
            let node = try InteractionManager.performAction(
                pid: pid, windowID: windowID, action: actionName,
                role: role, title: title, value: value, description: desc
            )
            return try jsonString(node)
        }
    }

    static let activate = MCPTool(
        name: "peek_activate",
        description: "Bring an app to the foreground and raise its window.",
        schema: windowTargetSchema
    ) { args in
        let (windowID, pid) = try await resolveWindow(from: args)
        let result = try InteractionManager.activate(pid: pid, windowID: windowID)
        return try jsonString(result)
    }

    static let capture = MCPTool(
        name: "peek_capture",
        description: "Capture a screenshot of a window to a PNG file.",
        schema: windowTargetSchema.merging(MCPSchema(properties: [
            "output": .string("Output file path (default: window_<id>.png)"),
            "x": .integer("Crop region X offset (window-relative pixels)"),
            "y": .integer("Crop region Y offset (window-relative pixels)"),
            "width": .integer("Crop region width"),
            "height": .integer("Crop region height"),
        ]))
    ) { args in
        let (windowID, _) = try await resolveWindow(from: args)
        let path = args["output"] as? String ?? "window_\(windowID).png"
        let crop: CGRect? = if let x = args["x"] as? Int, let y = args["y"] as? Int,
                               let w = args["width"] as? Int, let h = args["height"] as? Int {
            CGRect(x: x, y: y, width: w, height: h)
        } else {
            nil
        }
        let result = try await ScreenCaptureManager.capture(windowID: windowID, outputPath: path, crop: crop)
        return try jsonString(result)
    }

    static let menu = MCPTool(
        name: "peek_menu",
        description: "Inspect or click menu bar items. Without 'click', returns the full menu structure. With 'click', triggers a menu item by title. Use 'find' to search for items without clicking.",
        schema: windowTargetSchema.merging(MCPSchema(properties: [
            "click": .string("Menu item title to click (case-insensitive substring)"),
            "find": .string("Search for menu items by title (case-insensitive substring) — returns matches with their menu path"),
        ]))
    ) { args in
        let (windowID, pid) = try await resolveWindow(from: args)
        _ = try InteractionManager.activate(pid: pid, windowID: windowID)
        if let clickTitle = args["click"] as? String {
            let title = try MenuBarManager.clickMenuItem(pid: pid, title: clickTitle)
            return try jsonString(["title": title])
        } else if let findTitle = args["find"] as? String {
            let items = try MenuBarManager.findMenuItems(pid: pid, title: findTitle)
            return try jsonString(items)
        } else {
            let tree = try MenuBarManager.menuBar(pid: pid)
            return try jsonString(tree)
        }
    }

    static let doctor = MCPTool(
        name: "peek_doctor",
        description: "Check if required permissions (Accessibility, Screen Recording) are granted.",
        schema: MCPSchema(properties: [
            "prompt": .boolean("Prompt for missing permissions via System Settings"),
        ])
    ) { args in
        let prompt = args["prompt"] as? Bool ?? false
        let status = PermissionManager.checkAll(prompt: prompt)
        return try jsonString(status)
    }
}

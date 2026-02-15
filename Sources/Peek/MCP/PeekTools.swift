import CoreGraphics
import Foundation
import SwiftCliMcp

enum PeekTools {
    // MARK: - Helpers

    private static func jsonString(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8)!
    }

    private static func resolveWindow(from args: [String: Any]) throws -> (windowID: CGWindowID, pid: pid_t) {
        let windowID: CGWindowID
        if let id = args["window_id"] as? Int {
            windowID = CGWindowID(id)
        } else if let app = args["app"] as? String {
            guard let id = WindowManager.windowID(forApp: app) else {
                throw PeekError.windowNotFound(0)
            }
            windowID = id
        } else if let pidVal = args["pid"] as? Int {
            guard let id = WindowManager.windowID(forPID: pid_t(pidVal)) else {
                throw PeekError.windowNotFound(0)
            }
            windowID = id
        } else {
            throw PeekError.noWindows
        }

        guard let pid = WindowManager.pid(forWindowID: windowID) else {
            throw PeekError.windowNotFound(windowID)
        }
        return (windowID, pid)
    }

    // MARK: - Shared Schema Fragments

    private static let windowTargetSchema = """
    "window_id": { "type": "integer", "description": "Window ID (from peek_apps)" },
    "app": { "type": "string", "description": "App name (case-insensitive substring)" },
    "pid": { "type": "integer", "description": "Process ID" }
    """

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
        name: "peek_window",
        description: "Inspect the accessibility tree of a window. Returns the full UI element hierarchy.",
        schema: """
        {
            "properties": {
                \(windowTargetSchema),
                "depth": { "type": "integer", "description": "Maximum tree depth to traverse" }
            }
        }
        """
    ) { args in
        let (windowID, pid) = try resolveWindow(from: args)
        let depth = args["depth"] as? Int
        let tree = try AccessibilityTreeManager.inspect(pid: pid, windowID: windowID, maxDepth: depth)
        return try jsonString(tree)
    }

    static let find = MCPTool(
        name: "peek_find",
        description: "Search for UI elements by attributes or coordinates. Use role/title/value/desc for attribute search, or x/y for hit-test.",
        schema: """
        {
            "properties": {
                \(windowTargetSchema),
                "role": { "type": "string", "description": "Filter by role (exact match, e.g. Button)" },
                "title": { "type": "string", "description": "Filter by title (case-insensitive substring)" },
                "value": { "type": "string", "description": "Filter by value (case-insensitive substring)" },
                "desc": { "type": "string", "description": "Filter by description (case-insensitive substring)" },
                "x": { "type": "integer", "description": "Hit-test X screen coordinate (use with y instead of filters)" },
                "y": { "type": "integer", "description": "Hit-test Y screen coordinate (use with x instead of filters)" }
            }
        }
        """
    ) { args in
        let (windowID, pid) = try resolveWindow(from: args)

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
        description: "Click at screen coordinates.",
        schema: """
        {
            "properties": {
                "x": { "type": "integer", "description": "X coordinate" },
                "y": { "type": "integer", "description": "Y coordinate" }
            },
            "required": ["x", "y"]
        }
        """
    ) { args in
        guard let x = args["x"] as? Int, let y = args["y"] as? Int else {
            throw PeekError.elementNotFound
        }
        InteractionManager.click(x: Double(x), y: Double(y))
        return try jsonString(["x": x, "y": y])
    }

    static let type = MCPTool(
        name: "peek_type",
        description: "Type text via keyboard events.",
        schema: """
        {
            "properties": {
                "text": { "type": "string", "description": "The text to type" }
            },
            "required": ["text"]
        }
        """
    ) { args in
        guard let text = args["text"] as? String else {
            throw PeekError.elementNotFound
        }
        InteractionManager.type(text: text)
        return try jsonString(["characters": text.count])
    }

    static let action = MCPTool(
        name: "peek_action",
        description: "Perform an accessibility action (e.g. AXPress, AXConfirm) on a UI element matching the given filters.",
        schema: """
        {
            "properties": {
                \(windowTargetSchema),
                "action": { "type": "string", "description": "AX action (e.g. AXPress, AXConfirm, AXCancel, AXShowMenu)" },
                "role": { "type": "string", "description": "Filter by role" },
                "title": { "type": "string", "description": "Filter by title" },
                "value": { "type": "string", "description": "Filter by value" },
                "desc": { "type": "string", "description": "Filter by description" },
                "all": { "type": "boolean", "description": "Perform on all matches (default: first only)" }
            },
            "required": ["action"]
        }
        """
    ) { args in
        let (windowID, pid) = try resolveWindow(from: args)
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
        schema: """
        {
            "properties": {
                \(windowTargetSchema)
            }
        }
        """
    ) { args in
        let (windowID, pid) = try resolveWindow(from: args)
        let result = try InteractionManager.activate(pid: pid, windowID: windowID)
        return try jsonString(result)
    }

    static let capture = MCPTool(
        name: "peek_capture",
        description: "Capture a screenshot of a window to a PNG file.",
        schema: """
        {
            "properties": {
                \(windowTargetSchema),
                "output": { "type": "string", "description": "Output file path (default: window_<id>.png)" }
            }
        }
        """
    ) { args in
        let (windowID, _) = try resolveWindow(from: args)
        let path = args["output"] as? String ?? "window_\(windowID).png"
        let result = try ScreenCaptureManager.capture(windowID: windowID, outputPath: path)
        return try jsonString(result)
    }

    static let menu = MCPTool(
        name: "peek_menu",
        description: "Inspect or click menu bar items. Without 'click', returns the full menu structure. With 'click', triggers a menu item by title.",
        schema: """
        {
            "properties": {
                \(windowTargetSchema),
                "click": { "type": "string", "description": "Menu item title to click (case-insensitive substring)" }
            }
        }
        """
    ) { args in
        let (_, pid) = try resolveWindow(from: args)
        if let clickTitle = args["click"] as? String {
            let title = try MenuBarManager.clickMenuItem(pid: pid, title: clickTitle)
            return try jsonString(["title": title])
        } else {
            let tree = try MenuBarManager.menuBar(pid: pid)
            return try jsonString(tree)
        }
    }

    static let doctor = MCPTool(
        name: "peek_doctor",
        description: "Check if required permissions (Accessibility, Screen Recording) are granted.",
        schema: """
        {
            "properties": {
                "prompt": { "type": "boolean", "description": "Prompt for missing permissions via System Settings" }
            }
        }
        """
    ) { args in
        let prompt = args["prompt"] as? Bool ?? false
        let status = PermissionManager.checkAll(prompt: prompt)
        return try jsonString(status)
    }
}

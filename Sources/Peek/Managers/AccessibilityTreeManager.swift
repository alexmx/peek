import AppKit
import ApplicationServices
import Foundation

enum AccessibilityTreeManager {
    static let maxDepth = 50

    static func inspect(pid: pid_t, windowID: CGWindowID, maxDepth: Int? = nil) throws -> AXNode {
        let window = try findWindow(pid: pid, windowID: windowID)
        return buildNode(from: window, depth: 0, limit: maxDepth ?? self.maxDepth)
    }

    static func findWindow(pid: pid_t, windowID: CGWindowID) throws -> AXUIElement {
        try PermissionManager.requireAccessibility()

        if let window = axWindow(pid: pid, windowID: windowID) {
            return window
        }

        // AX tree inaccessible — app may be on another Space. Activate and retry.
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            throw PeekError.noWindows
        }
        app.activate()

        for _ in 0..<20 {
            usleep(100_000) // 100ms
            if let window = axWindow(pid: pid, windowID: windowID) {
                return window
            }
        }

        throw PeekError.noWindows
    }

    /// Try to get an AXUIElement for the window. Returns nil if the AX tree is inaccessible.
    private static func axWindow(pid: pid_t, windowID: CGWindowID) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            return nil
        }
        return windows.first { win in
            var id: CGWindowID = 0
            return _AXUIElementGetWindow(win, &id) == .success && id == windowID
        } ?? windows[0]
    }

    /// Build an AXNode tree from an AXUIElement.
    static func buildNode(from element: AXUIElement, depth: Int = 0, limit: Int = maxDepth) -> AXNode {
        let role = stripAXPrefix(axString(of: element, key: kAXRoleAttribute) ?? "unknown")
        let title = axString(of: element, key: kAXTitleAttribute)
        let value = axString(of: element, key: kAXValueAttribute)
        let description = axString(of: element, key: kAXDescriptionAttribute)

        var childNodes: [AXNode] = []
        if depth < limit, let children = axChildren(of: element) {
            childNodes = children.map { buildNode(from: $0, depth: depth + 1, limit: limit) }
        }

        return AXNode(
            role: role,
            title: title,
            value: value,
            description: description,
            frame: axFrameInfo(of: element),
            children: childNodes
        )
    }

    /// Search the tree for nodes matching the given criteria.
    static func find(
        pid: pid_t,
        windowID: CGWindowID,
        role: String?,
        title: String?,
        value: String?,
        description: String?
    ) throws -> [AXNode] {
        let window = try findWindow(pid: pid, windowID: windowID)
        let tree = buildNode(from: window, depth: 0)
        var results: [AXNode] = []
        searchNode(tree, role: role.map(stripAXPrefix), title: title, value: value, description: description, results: &results)
        return results
    }

    private static func searchNode(
        _ node: AXNode,
        role: String?,
        title: String?,
        value: String?,
        description: String?,
        results: inout [AXNode]
    ) {
        if node.matches(role: role, title: title, value: value, description: description) {
            results.append(node.leaf)
        }

        for child in node.children {
            searchNode(child, role: role, title: title, value: value, description: description, results: &results)
        }
    }

    /// Find the deepest element at the given screen coordinates.
    static func elementAt(
        pid: pid_t,
        windowID: CGWindowID,
        x: Int,
        y: Int
    ) throws -> AXNode? {
        let window = try findWindow(pid: pid, windowID: windowID)
        let tree = buildNode(from: window, depth: 0)
        return deepestNode(in: tree, x: x, y: y)
    }

    private static func deepestNode(in node: AXNode, x: Int, y: Int) -> AXNode? {
        guard let f = node.frame,
              x >= f.x, x < f.x + f.width,
              y >= f.y, y < f.y + f.height
        else { return nil }

        // Try to find a deeper match in children
        for child in node.children {
            if let deeper = deepestNode(in: child, x: x, y: y) {
                return deeper
            }
        }

        // This node contains the point but no child does — it's the deepest
        return node.leaf
    }
}

/// Private API to extract a CGWindowID from an AXUIElement.
/// Apple provides no public bridge between the Accessibility and CGWindow worlds,
/// so this is the standard workaround used by tools like Hammerspoon and yabai.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(
    _ element: AXUIElement,
    _ windowID: UnsafeMutablePointer<CGWindowID>
) -> AXError

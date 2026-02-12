import ApplicationServices
import Foundation

enum AccessibilityTreeManager {
    private static let maxDepth = 50

    static func inspect(pid: pid_t, windowID: CGWindowID) throws -> AXNode {
        let window = try findWindow(pid: pid, windowID: windowID)
        return buildNode(from: window, depth: 0)
    }

    static func findWindow(pid: pid_t, windowID: CGWindowID) throws -> AXUIElement {
        try PermissionManager.requireAccessibility()

        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            throw PeekError.noWindows
        }

        return windows.first { win in
            var id: CGWindowID = 0
            return _AXUIElementGetWindow(win, &id) == .success && id == windowID
        } ?? windows[0]
    }

    /// Build an AXNode tree from an AXUIElement.
    static func buildNode(from element: AXUIElement, depth: Int = 0) -> AXNode {
        let role = axString(of: element, key: kAXRoleAttribute) ?? "unknown"
        let title = axString(of: element, key: kAXTitleAttribute)
        let value = axString(of: element, key: kAXValueAttribute)
        let description = axString(of: element, key: kAXDescriptionAttribute)

        var childNodes: [AXNode] = []
        if depth < maxDepth, let children = axChildren(of: element) {
            childNodes = children.map { buildNode(from: $0, depth: depth + 1) }
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
        searchNode(tree, role: role, title: title, value: value, description: description, results: &results)
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
        var matches = true
        if let role, node.role != role { matches = false }
        if let title, node.title?.localizedCaseInsensitiveContains(title) != true { matches = false }
        if let value, node.value?.localizedCaseInsensitiveContains(value) != true { matches = false }
        if let description, node.description?.localizedCaseInsensitiveContains(description) != true { matches = false }

        if matches {
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

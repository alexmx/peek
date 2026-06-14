import ApplicationServices
import Foundation

enum MenuBarManager {
    private static let maxDepth = 20

    static func menuBar(pid: pid_t) throws -> MenuNode {
        let menuBarEl = try AccessibilityManager.menuBar(pid: pid)
        return buildMenuNode(from: menuBarEl)
    }

    /// Return the subtree at the given path (segments separated by ">"), so callers
    /// can scope a menu read to a single submenu (e.g. "Debug" or "Edit > Find")
    /// instead of dumping the entire menu bar. Throws `menuItemNotFound` if no node
    /// along the path matches.
    static func menuSubtree(pid: pid_t, path: String) throws -> MenuNode {
        let segments = path.split(separator: ">").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !segments.isEmpty else {
            return try menuBar(pid: pid)
        }
        let tree = try menuBar(pid: pid)
        guard let node = findByPath(in: tree, segments: segments) else {
            throw PeekError.menuItemNotFound(path)
        }
        return node
    }

    private static func findByPath(in node: MenuNode, segments: [String]) -> MenuNode? {
        guard let head = segments.first else { return node }
        let rest = Array(segments.dropFirst())
        for child in node.children {
            if child.title.localizedCaseInsensitiveCompare(head) == .orderedSame {
                if let found = findByPath(in: child, segments: rest) {
                    return found
                }
            }
            // Descend through unnamed wrappers (AXMenu containers) without consuming a segment.
            if child.title.isEmpty {
                if let found = findByPath(in: child, segments: segments) {
                    return found
                }
            }
        }
        return nil
    }

    /// Search for menu items matching a title (case-insensitive substring).
    static func findMenuItems(pid: pid_t, title: String) throws -> [MenuNode] {
        let menuBarEl = try AccessibilityManager.menuBar(pid: pid)
        var results: [MenuNode] = []
        searchMenuElements(in: menuBarEl, title: title, path: [], depth: 0, results: &results)
        guard !results.isEmpty else {
            throw PeekError.menuItemNotFound(title)
        }
        return results
    }

    private static func searchMenuElements(
        in element: AXUIElement,
        title: String,
        path: [String],
        depth: Int,
        results: inout [MenuNode]
    ) {
        guard depth < maxDepth else { return }
        let elementTitle = AXBridge.title(of: element) ?? ""
        let currentPath = elementTitle.isEmpty ? path : path + [elementTitle]

        if AXBridge.elementMatches(
            element, role: "MenuItem", title: title, value: nil, description: nil, enabled: nil
        ), !elementTitle.isEmpty {
            let node = AXBridge.nodeFromElement(element)
            let shortcut = AXBridge.menuShortcut(of: element)
            let menuNode = MenuNode(
                title: node.title ?? "",
                role: node.role,
                enabled: node.enabled ?? true,
                shortcut: shortcut,
                children: []
            )
            results.append(menuNode.withPath(currentPath.joined(separator: " > ")))
        }

        if let children = AXBridge.children(of: element) {
            for child in children {
                searchMenuElements(in: child, title: title, path: currentPath, depth: depth + 1, results: &results)
            }
        }
    }

    /// Find and press a menu item by title (case-insensitive substring match).
    static func clickMenuItem(pid: pid_t, title: String) throws -> String {
        let menuBarEl = try AccessibilityManager.menuBar(pid: pid)

        guard let element = findMenuItem(in: menuBarEl, title: title, depth: 0) else {
            throw PeekError.menuItemNotFound(title)
        }

        try AXBridge.performAction("Press", on: element)
        return AXBridge.nodeFromElement(element).title ?? title
    }

    private static func findMenuItem(in element: AXUIElement, title: String, depth: Int) -> AXUIElement? {
        guard depth < maxDepth else { return nil }

        let node = AXBridge.nodeFromElement(element)

        if node.role == "MenuItem", let itemTitle = node.title, !itemTitle.isEmpty,
           itemTitle.localizedCaseInsensitiveContains(title),
           node.enabled != false {
            return element
        }

        if let children = AXBridge.children(of: element) {
            for child in children {
                if let found = findMenuItem(in: child, title: title, depth: depth + 1) {
                    return found
                }
            }
        }

        return nil
    }

    /// Search recursively through menu tree for matching items.
    static func searchMenuNode(_ node: MenuNode, title: String, path: [String], results: inout [MenuNode]) {
        let currentPath = node.title.isEmpty ? path : path + [node.title]

        if node.role == "MenuItem", !node.title.isEmpty,
           node.title.localizedCaseInsensitiveContains(title) {
            results.append(node.withPath(currentPath.joined(separator: " > ")))
        }

        for child in node.children {
            searchMenuNode(child, title: title, path: currentPath, results: &results)
        }
    }

    private static func buildMenuNode(from element: AXUIElement, depth: Int = 0) -> MenuNode {
        guard depth < maxDepth else {
            return MenuNode(title: "", role: "unknown", enabled: false, shortcut: nil, children: [])
        }

        let node = AXBridge.nodeFromElement(element)
        let shortcut = AXBridge.menuShortcut(of: element)

        var childNodes: [MenuNode] = []
        if let children = AXBridge.children(of: element) {
            childNodes = children.map { buildMenuNode(from: $0, depth: depth + 1) }
        }

        return MenuNode(
            title: node.title ?? "",
            role: node.role,
            enabled: node.enabled ?? true,
            shortcut: shortcut,
            children: childNodes
        )
    }
}

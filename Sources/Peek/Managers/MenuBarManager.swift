import ApplicationServices
import Foundation

enum MenuBarManager {
    private static let maxDepth = 20

    static func menuBar(pid: pid_t) throws -> MenuNode {
        let menuBarEl = try AXElement.menuBar(pid: pid)
        return buildMenuNode(from: menuBarEl)
    }

    /// Search for menu items matching a title (case-insensitive substring).
    static func findMenuItems(pid: pid_t, title: String) throws -> [MenuNode] {
        let menuBarEl = try AXElement.menuBar(pid: pid)
        let tree = buildMenuNode(from: menuBarEl)
        var results: [MenuNode] = []
        searchMenuNode(tree, title: title, path: [], results: &results)
        guard !results.isEmpty else {
            throw PeekError.menuItemNotFound(title)
        }
        return results
    }

    /// Find and press a menu item by title (case-insensitive substring match).
    static func clickMenuItem(pid: pid_t, title: String) throws -> String {
        let menuBarEl = try AXElement.menuBar(pid: pid)

        guard let element = findMenuItem(in: menuBarEl, title: title, depth: 0) else {
            throw PeekError.menuItemNotFound(title)
        }

        try AXElement.performAction("Press", on: element)
        return AXElement.nodeFromElement(element).title ?? title
    }

    private static func findMenuItem(in element: AXUIElement, title: String, depth: Int) -> AXUIElement? {
        guard depth < maxDepth else { return nil }

        let node = AXElement.nodeFromElement(element)

        if node.role == "MenuItem", let itemTitle = node.title, !itemTitle.isEmpty,
           itemTitle.localizedCaseInsensitiveContains(title),
           node.enabled != false {
            return element
        }

        if let children = AXElement.children(of: element) {
            for child in children {
                if let found = findMenuItem(in: child, title: title, depth: depth + 1) {
                    return found
                }
            }
        }

        return nil
    }

    private static func searchMenuNode(_ node: MenuNode, title: String, path: [String], results: inout [MenuNode]) {
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

        let node = AXElement.nodeFromElement(element)
        let shortcut = AXElement.menuShortcut(of: element)

        var childNodes: [MenuNode] = []
        if let children = AXElement.children(of: element) {
            childNodes = children.map { buildMenuNode(from: $0, depth: depth + 1) }
        }

        return MenuNode(title: node.title ?? "", role: node.role, enabled: node.enabled ?? true, shortcut: shortcut, children: childNodes)
    }
}

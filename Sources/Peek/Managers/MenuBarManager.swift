import ApplicationServices
import Foundation

enum MenuBarManager {
    private static let maxDepth = 20

    /// Resolve the requested menu-bar root: the main bar, or the status-item
    /// "extras" bar (NSStatusItem / SwiftUI MenuBarExtra) when `extras` is set.
    private static func root(pid: pid_t, extras: Bool) throws -> AXUIElement {
        extras
            ? try AccessibilityManager.extrasMenuBar(pid: pid)
            : try AccessibilityManager.menuBar(pid: pid)
    }

    static func menuBar(pid: pid_t, extras: Bool = false) throws -> MenuNode {
        let menuBarEl = try root(pid: pid, extras: extras)
        return buildMenuNode(from: menuBarEl)
    }

    /// Return the subtree at the given path (segments separated by ">"), so callers
    /// can scope a menu read to a single submenu (e.g. "Debug" or "Edit > Find")
    /// instead of dumping the entire menu bar. Throws `menuItemNotFound` if no node
    /// along the path matches.
    static func menuSubtree(pid: pid_t, path: String, extras: Bool = false) throws -> MenuNode {
        let segments = path.split(separator: ">").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !segments.isEmpty else {
            return try menuBar(pid: pid, extras: extras)
        }
        let tree = try menuBar(pid: pid, extras: extras)
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
    static func findMenuItems(pid: pid_t, title: String, extras: Bool = false) throws -> [MenuNode] {
        let menuBarEl = try root(pid: pid, extras: extras)
        var results: [MenuNode] = []
        searchMenuElements(in: menuBarEl, title: title, path: [], depth: 0, extras: extras, results: &results)
        guard !results.isEmpty else {
            throw PeekError.menuItemNotFound(title)
        }
        return results
    }

    /// Best display label for a menu element: AXTitle, falling back to AXDescription.
    /// Status items commonly expose their label only via description.
    private static func menuLabel(_ node: AXNode) -> String {
        if let title = node.title, !title.isEmpty { return title }
        return node.description ?? ""
    }

    /// Roles that count as an actionable menu entry. In the extras bar the top-level
    /// status items are `MenuBarItem`s (pressing one opens its menu), so include them.
    private static func isMenuEntry(role: String, extras: Bool) -> Bool {
        role == "MenuItem" || (extras && role == "MenuBarItem")
    }

    private static func searchMenuElements(
        in element: AXUIElement,
        title: String,
        path: [String],
        depth: Int,
        extras: Bool,
        results: inout [MenuNode]
    ) {
        guard depth < maxDepth else { return }
        let node = AXBridge.nodeFromElement(element)
        let label = menuLabel(node)
        let currentPath = label.isEmpty ? path : path + [label]

        if isMenuEntry(role: node.role, extras: extras), !label.isEmpty,
           label.localizedCaseInsensitiveContains(title) {
            let shortcut = AXBridge.menuShortcut(of: element)
            let menuNode = MenuNode(
                title: label,
                role: node.role,
                enabled: node.enabled ?? true,
                shortcut: shortcut,
                children: []
            )
            results.append(menuNode.withPath(currentPath.joined(separator: " > ")))
        }

        if let children = AXBridge.children(of: element) {
            for child in children {
                searchMenuElements(
                    in: child, title: title, path: currentPath, depth: depth + 1, extras: extras, results: &results
                )
            }
        }
    }

    /// Find and press a menu item by title (case-insensitive substring match).
    /// With `extras`, a top-level status item (MenuBarItem) can be the target —
    /// pressing it opens its menu, whose items become AX-visible for a follow-up call.
    static func clickMenuItem(pid: pid_t, title: String, extras: Bool = false) throws -> String {
        let menuBarEl = try root(pid: pid, extras: extras)

        guard let (element, label) = findMenuItem(in: menuBarEl, title: title, depth: 0, extras: extras) else {
            throw PeekError.menuItemNotFound(title)
        }

        try AXBridge.performAction("Press", on: element)
        return label
    }

    private static func findMenuItem(
        in element: AXUIElement,
        title: String,
        depth: Int,
        extras: Bool
    ) -> (AXUIElement, String)? {
        guard depth < maxDepth else { return nil }

        let node = AXBridge.nodeFromElement(element)
        let label = menuLabel(node)

        if isMenuEntry(role: node.role, extras: extras), !label.isEmpty,
           label.localizedCaseInsensitiveContains(title),
           node.enabled != false {
            return (element, label)
        }

        if let children = AXBridge.children(of: element) {
            for child in children {
                if let found = findMenuItem(in: child, title: title, depth: depth + 1, extras: extras) {
                    return found
                }
            }
        }

        return nil
    }

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
            title: menuLabel(node),
            role: node.role,
            enabled: node.enabled ?? true,
            shortcut: shortcut,
            children: childNodes
        )
    }
}

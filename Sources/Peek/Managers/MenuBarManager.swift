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
        let menuBarEl = try root(pid: pid, extras: extras)
        guard let element = findElementByPath(in: menuBarEl, segments: pathSegments(path), depth: 0) else {
            throw PeekError.menuItemNotFound(path)
        }
        return buildMenuNode(from: element)
    }

    /// Split a menu path ("File > Open Recent") into trimmed, non-empty segments.
    static func pathSegments(_ path: String) -> [String] {
        path.split(separator: ">").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
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

    /// Find and press a menu item. `title` is a case-insensitive substring of the item's
    /// label, or a full path as `find` returns it ("File > Open Recent > Clear Menu") whose
    /// last segment is the item. `path` scopes the search to a submenu; both forms combine.
    /// Scoping disambiguates items that share a label across menus (Apple > Recent Items >
    /// Clear Menu vs File > Open Recent > Clear Menu). An exact label match wins over a
    /// substring match, so "Close" doesn't press "Close All" just because it comes first.
    /// With `extras`, a top-level status item (MenuBarItem) can be the target —
    /// pressing it opens its menu, whose items become AX-visible for a follow-up call.
    ///
    /// Activates the app first so the opened menu renders. Best-effort: an activation
    /// timeout doesn't block the press, which is an AX action and works regardless.
    static func clickMenuItem(
        pid: pid_t,
        title: String,
        path: String? = nil,
        extras: Bool = false
    ) async throws -> (title: String, path: String) {
        do {
            _ = try await InteractionManager.activateApp(pid: pid)
        } catch PeekError.activationFailed {
            // Proceed: the press below doesn't need the app frontmost.
        }

        let menuBarEl = try root(pid: pid, extras: extras)

        var titleSegments = pathSegments(title)
        guard let leaf = titleSegments.popLast() else {
            throw PeekError.menuItemNotFound(title)
        }
        let scope = pathSegments(path ?? "") + titleSegments

        let scopeEl: AXUIElement
        if scope.isEmpty {
            scopeEl = menuBarEl
        } else {
            guard let el = findElementByPath(in: menuBarEl, segments: scope, depth: 0) else {
                throw PeekError.menuItemNotFound(scope.joined(separator: " > "))
            }
            scopeEl = el
        }

        var fallback: (element: AXUIElement, path: [String])?
        guard let target = findClickTarget(
            in: scopeEl, title: leaf, path: scope, depth: 0, extras: extras, fallback: &fallback
        ) ?? fallback else {
            throw PeekError.menuItemNotFound((scope + [leaf]).joined(separator: " > "))
        }

        try AXBridge.performAction("Press", on: target.element)
        return (target.path.last ?? leaf, target.path.joined(separator: " > "))
    }

    /// How a menu label matches a click query: exact (case-insensitive) or substring.
    enum ClickMatch {
        case exact, substring
    }

    static func clickMatch(label: String, query: String) -> ClickMatch? {
        guard !label.isEmpty else { return nil }
        if label.localizedCaseInsensitiveCompare(query) == .orderedSame { return .exact }
        if label.localizedCaseInsensitiveContains(query) { return .substring }
        return nil
    }

    /// Walk the AX menu tree along `segments` (exact, case-insensitive labels), descending
    /// through unnamed AXMenu wrappers. Empty `segments` returns `element` itself.
    private static func findElementByPath(in element: AXUIElement, segments: [String], depth: Int) -> AXUIElement? {
        guard let head = segments.first else { return element }
        guard depth < maxDepth, let children = AXBridge.children(of: element) else { return nil }
        let rest = Array(segments.dropFirst())
        for child in children {
            let label = menuLabel(AXBridge.nodeFromElement(child))
            if label.localizedCaseInsensitiveCompare(head) == .orderedSame,
               let found = findElementByPath(in: child, segments: rest, depth: depth + 1) {
                return found
            }
            if label.isEmpty, let found = findElementByPath(in: child, segments: segments, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    /// DFS below `element` for the item to press. Returns the first enabled exact label
    /// match immediately; records the first enabled substring match in `fallback`.
    private static func findClickTarget(
        in element: AXUIElement,
        title: String,
        path: [String],
        depth: Int,
        extras: Bool,
        fallback: inout (element: AXUIElement, path: [String])?
    ) -> (element: AXUIElement, path: [String])? {
        guard depth < maxDepth, let children = AXBridge.children(of: element) else { return nil }

        for child in children {
            let node = AXBridge.nodeFromElement(child)
            let label = menuLabel(node)
            let childPath = label.isEmpty ? path : path + [label]

            if isMenuEntry(role: node.role, extras: extras), node.enabled != false,
               let match = clickMatch(label: label, query: title) {
                switch match {
                case .exact:
                    return (child, childPath)
                case .substring:
                    if fallback == nil { fallback = (child, childPath) }
                }
            }

            if let found = findClickTarget(
                in: child, title: title, path: childPath, depth: depth + 1, extras: extras, fallback: &fallback
            ) {
                return found
            }
        }

        return nil
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

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// High-level accessibility operations: window/menu bar resolution, tree building, and element search.
enum AccessibilityManager {
    static let maxDepth = 50

    // MARK: - Resolution

    /// Resolve a window element, activating the app and retrying if needed.
    static func resolveWindow(pid: pid_t, windowID: CGWindowID) throws -> AXUIElement {
        try PermissionManager.requireAccessibility()

        if let w = AXBridge.window(pid: pid, windowID: windowID) {
            return w
        }

        // AX tree inaccessible — app may be on another Space. Activate and retry.
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            throw PeekError.noWindows
        }
        app.activate()

        for _ in 0..<20 {
            usleep(100_000) // 100ms
            if let w = AXBridge.window(pid: pid, windowID: windowID) {
                return w
            }
        }

        throw PeekError.noWindows
    }

    /// Get the menu bar element for an application, activating if needed.
    static func menuBar(pid: pid_t) throws -> AXUIElement {
        try PermissionManager.requireAccessibility()

        let app = AXBridge.application(pid: pid)
        var ref: AnyObject?
        var result = AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &ref)

        if result == .success, let ref {
            // swiftlint:disable:next force_cast
            return ref as! AXUIElement
        }

        // Menu bar not accessible — app may be on another Space. Activate and retry.
        guard let runningApp = NSRunningApplication(processIdentifier: pid) else {
            throw PeekError.noMenuBar(pid)
        }
        runningApp.activate()

        for _ in 0..<20 {
            usleep(100_000) // 100ms
            result = AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &ref)
            if result == .success, let ref {
                // swiftlint:disable:next force_cast
                return ref as! AXUIElement
            }
        }

        throw PeekError.noMenuBar(pid)
    }

    // MARK: - Tree Building

    /// Recursively build a full AXNode tree from an element.
    static func buildTree(from element: AXUIElement, depth: Int = 0, limit: Int = maxDepth) -> AXNode {
        let base = AXBridge.nodeFromElement(element)

        var childNodes: [AXNode] = []
        if depth < limit, let children = AXBridge.children(of: element) {
            childNodes = children.map { buildTree(from: $0, depth: depth + 1, limit: limit) }
        }

        return AXNode(
            role: base.role,
            title: base.title,
            value: base.value,
            description: base.description,
            enabled: base.enabled,
            frame: base.frame,
            children: childNodes
        )
    }

    // MARK: - Inspection

    static func inspect(pid: pid_t, windowID: CGWindowID, maxDepth: Int? = nil) throws -> AXNode {
        let window = try resolveWindow(pid: pid, windowID: windowID)
        return buildTree(from: window, depth: 0, limit: maxDepth ?? Self.maxDepth)
    }

    // MARK: - Element Search

    /// A found element: the live AXUIElement reference plus its AXNode snapshot.
    struct ElementMatch {
        let ref: AXUIElement
        let node: AXNode
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
        let window = try resolveWindow(pid: pid, windowID: windowID)
        return findAll(in: window, role: role, title: title, value: value, description: description)
            .map(\.node)
    }

    /// Find the deepest element at the given screen coordinates.
    static func elementAt(
        pid: pid_t,
        windowID: CGWindowID,
        x: Int,
        y: Int
    ) throws -> AXNode? {
        let window = try resolveWindow(pid: pid, windowID: windowID)
        let tree = buildTree(from: window, depth: 0)
        return deepestNode(in: tree, x: x, y: y)
    }

    /// DFS to find the first element matching filters.
    static func findFirst(
        in element: AXUIElement,
        role: String?,
        title: String?,
        value: String?,
        description: String?
    ) -> ElementMatch? {
        searchFirst(
            in: element,
            role: role.map(AXBridge.stripAXPrefix),
            title: title,
            value: value,
            description: description,
            depth: 0
        )
    }

    /// DFS to find all elements matching filters.
    static func findAll(
        in element: AXUIElement,
        role: String?,
        title: String?,
        value: String?,
        description: String?
    ) -> [ElementMatch] {
        var results: [ElementMatch] = []
        searchAll(
            in: element,
            role: role.map(AXBridge.stripAXPrefix),
            title: title,
            value: value,
            description: description,
            depth: 0,
            results: &results
        )
        return results
    }

    // MARK: - Private Search

    private static func searchFirst(
        in element: AXUIElement,
        role: String?,
        title: String?,
        value: String?,
        description: String?,
        depth: Int
    ) -> ElementMatch? {
        guard depth < maxDepth else { return nil }

        let node = AXBridge.nodeFromElement(element)
        if node.matches(role: role, title: title, value: value, description: description) {
            return ElementMatch(ref: element, node: node)
        }

        if let children = AXBridge.children(of: element) {
            for child in children {
                if let found = searchFirst(
                    in: child,
                    role: role,
                    title: title,
                    value: value,
                    description: description,
                    depth: depth + 1
                ) {
                    return found
                }
            }
        }

        return nil
    }

    private static func searchAll(
        in element: AXUIElement,
        role: String?,
        title: String?,
        value: String?,
        description: String?,
        depth: Int,
        results: inout [ElementMatch]
    ) {
        guard depth < maxDepth else { return }

        let node = AXBridge.nodeFromElement(element)
        if node.matches(role: role, title: title, value: value, description: description) {
            results.append(ElementMatch(ref: element, node: node))
        }

        if let children = AXBridge.children(of: element) {
            for child in children {
                searchAll(
                    in: child,
                    role: role,
                    title: title,
                    value: value,
                    description: description,
                    depth: depth + 1,
                    results: &results
                )
            }
        }
    }

    // MARK: - Hit Testing

    /// Find the deepest node containing the given point.
    static func deepestNode(in node: AXNode, x: Int, y: Int) -> AXNode? {
        guard let f = node.frame,
              x >= f.x, x < f.x + f.width,
              y >= f.y, y < f.y + f.height
        else { return nil }

        for child in node.children {
            if let deeper = deepestNode(in: child, x: x, y: y) {
                return deeper
            }
        }

        return node.withoutChildren
    }
}

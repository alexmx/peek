import CoreGraphics
import Foundation

enum AccessibilityTreeManager {
    static func inspect(pid: pid_t, windowID: CGWindowID, maxDepth: Int? = nil) throws -> AXNode {
        let window = try AXElement.resolveWindow(pid: pid, windowID: windowID)
        return AXElement.buildTree(from: window, depth: 0, limit: maxDepth ?? AXElement.maxDepth)
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
        let window = try AXElement.resolveWindow(pid: pid, windowID: windowID)
        let tree = AXElement.buildTree(from: window, depth: 0)
        var results: [AXNode] = []
        searchNode(
            tree,
            role: role.map(AXElement.stripAXPrefix),
            title: title,
            value: value,
            description: description,
            results: &results
        )
        return results
    }

    /// Search recursively through a node tree for matches.
    static func searchNode(
        _ node: AXNode,
        role: String?,
        title: String?,
        value: String?,
        description: String?,
        results: inout [AXNode]
    ) {
        if node.matches(role: role, title: title, value: value, description: description) {
            results.append(node.withoutChildren)
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
        let window = try AXElement.resolveWindow(pid: pid, windowID: windowID)
        let tree = AXElement.buildTree(from: window, depth: 0)
        return deepestNode(in: tree, x: x, y: y)
    }

    /// Find the deepest node containing the given point.
    static func deepestNode(in node: AXNode, x: Int, y: Int) -> AXNode? {
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
        return node.withoutChildren
    }
}

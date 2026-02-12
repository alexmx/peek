import ArgumentParser
import CoreGraphics
import Foundation

struct InspectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect the accessibility tree of a window"
    )

    @Argument(help: "The window ID to inspect")
    var windowID: UInt32

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    func run() throws {
        guard let pid = WindowManager.pid(forWindowID: windowID) else {
            throw PeekError.windowNotFound(windowID)
        }

        let tree = try AccessibilityTree.inspect(pid: pid, windowID: windowID)

        if json {
            try printJSON(tree)
        } else {
            printNode(tree)
        }
    }

    private func printNode(_ node: AXNode, prefix: String = "", isLast: Bool = true, isRoot: Bool = true) {
        let connector = isRoot ? "" : (isLast ? "└── " : "├── ")
        let role = node.role.hasPrefix("AX") ? String(node.role.dropFirst(2)) : node.role
        var line = "\(prefix)\(connector)\(role)"
        if let title = node.title, !title.isEmpty { line += "  \"\(title)\"" }
        if let value = node.value, !value.isEmpty { line += "  value=\"\(value)\"" }
        if let desc = node.description, !desc.isEmpty { line += "  desc=\"\(desc)\"" }
        if let f = node.frame {
            line += "  (\(f.x), \(f.y)) \(f.width)x\(f.height)"
        }
        print(line)

        let childPrefix = isRoot ? "" : (prefix + (isLast ? "    " : "│   "))
        for (index, child) in node.children.enumerated() {
            printNode(child, prefix: childPrefix, isLast: index == node.children.count - 1, isRoot: false)
        }
    }
}

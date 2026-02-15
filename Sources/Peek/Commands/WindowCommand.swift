import ArgumentParser
import CoreGraphics
import Foundation

struct WindowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tree",
        abstract: "Inspect the accessibility tree of a window"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .long, help: "Maximum tree depth to traverse")
    var depth: Int?

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func run() async throws {
        let resolved = try await target.resolve()

        let tree = try AccessibilityTreeManager.inspect(pid: resolved.pid, windowID: resolved.windowID, maxDepth: depth)

        if format == .json {
            try printJSON(tree)
        } else {
            printNode(tree)
        }
    }

    private func printNode(_ node: AXNode, prefix: String = "", isLast: Bool = true, isRoot: Bool = true) {
        let connector = isRoot ? "" : (isLast ? "└── " : "├── ")
        print("\(prefix)\(connector)\(node.formatted)")

        let childPrefix = isRoot ? "" : (prefix + (isLast ? "    " : "│   "))
        for (index, child) in node.children.enumerated() {
            printNode(child, prefix: childPrefix, isLast: index == node.children.count - 1, isRoot: false)
        }
    }
}

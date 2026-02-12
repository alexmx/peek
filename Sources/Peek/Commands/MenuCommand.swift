import ArgumentParser
import Foundation

struct MenuCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "menu",
        abstract: "Dump the menu bar structure of an application"
    )

    @Argument(help: "The PID of the application")
    var pid: Int32

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func run() throws {
        let tree = try MenuBarManager.menuBar(pid: pid)

        if format == .json {
            try printJSON(tree)
        } else {
            printMenu(tree)
        }
    }

    private func printMenu(_ node: MenuNode) {
        for item in node.children {
            printMenuItem(item, depth: 0)
        }
    }

    private func printMenuItem(_ node: MenuNode, depth: Int) {
        if node.role == "AXMenu" {
            for child in node.children {
                printMenuItem(child, depth: depth)
            }
            return
        }

        let indent = String(repeating: "  ", count: depth)

        if node.title.isEmpty, node.role == "AXMenuItem" {
            print("\(indent)---")
            return
        }

        guard !node.title.isEmpty else { return }

        var line = "\(indent)\(node.title)"
        if !node.enabled { line += "  (disabled)" }
        if let shortcut = node.shortcut { line += "  \(shortcut)" }
        if !node.children.isEmpty, node.role != "AXMenuBarItem" {
            line += "  >"
        }
        print(line)

        for child in node.children {
            printMenuItem(child, depth: depth + 1)
        }
    }
}

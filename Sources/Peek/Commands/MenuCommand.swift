import ArgumentParser
import Foundation

struct MenuCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "menu",
        abstract: "Dump the menu bar structure of an application"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .long, help: "Click a menu item by title (case-insensitive substring)")
    var click: String?

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    struct ClickResult: Encodable {
        let title: String
    }

    func run() throws {
        let windowID = try target.resolve()
        guard let pid = WindowManager.pid(forWindowID: windowID) else {
            throw PeekError.windowNotFound(windowID)
        }

        if let click {
            let title = try MenuBarManager.clickMenuItem(pid: pid, title: click)
            if format == .json {
                try printJSON(ClickResult(title: title))
            } else {
                print("Clicked menu item: \(title)")
            }
            return
        }

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

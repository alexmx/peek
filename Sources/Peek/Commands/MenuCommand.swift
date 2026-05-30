import AppKit
import ArgumentParser
import Foundation

struct MenuCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "menu",
        abstract: "Inspect the menu bar structure of an application"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .long, help: "Click a menu item by title (case-insensitive substring)")
    var click: String?

    @Option(name: .long, help: "Search for menu items by title (case-insensitive substring)")
    var find: String?

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    struct ClickResult: Encodable {
        let title: String
    }

    func run() async throws {
        let pid = try await resolvePID()

        if let click {
            _ = try? await InteractionManager.activateApp(pid: pid)
            let title = try MenuBarManager.clickMenuItem(pid: pid, title: click)
            switch format {
            case .json:
                try printJSON(ClickResult(title: title))
            case .toon:
                try printTOON(ClickResult(title: title))
            case .default:
                print("Clicked menu item: \(title)")
            }
            return
        }

        if let find {
            let items = try MenuBarManager.findMenuItems(pid: pid, title: find)
            switch format {
            case .json:
                try printJSON(items)
            case .toon:
                try printTOON(items)
            case .default:
                for item in items {
                    var line = item.title
                    if !item.enabled { line += "  (disabled)" }
                    if let shortcut = item.shortcut { line += "  \(shortcut)" }
                    if let path = item.path { line += "  [\(path)]" }
                    print(line)
                }
                print("\n\(items.count) item(s) found.")
            }
            return
        }

        let tree = try MenuBarManager.menuBar(pid: pid)

        switch format {
        case .json:
            try printJSON(tree)
        case .toon:
            try printTOON(tree)
        case .default:
            printMenu(tree)
        }
    }

    /// Resolve just the target PID without requiring a window. Menu bar is per-app.
    private func resolvePID() async throws -> pid_t {
        if let pid = target.pid { return pid }
        if let app = target.app {
            for running in NSWorkspace.shared.runningApplications
                where running.activationPolicy == .regular
                && running.localizedName?.localizedCaseInsensitiveContains(app) == true {
                return running.processIdentifier
            }
            throw PeekError.appNotFound(app)
        }
        // Fall through to window-based resolution if user passed a window ID.
        let resolved = try await target.resolve()
        return resolved.pid
    }

    private func printMenu(_ node: MenuNode) {
        for item in node.children {
            printMenuItem(item, depth: 0)
        }
    }

    private func printMenuItem(_ node: MenuNode, depth: Int) {
        if node.role == "Menu" {
            for child in node.children {
                printMenuItem(child, depth: depth)
            }
            return
        }

        let indent = String(repeating: "  ", count: depth)

        if node.title.isEmpty, node.role == "MenuItem" {
            print("\(indent)---")
            return
        }

        guard !node.title.isEmpty else { return }

        var line = "\(indent)\(node.title)"
        if !node.enabled { line += "  (disabled)" }
        if let shortcut = node.shortcut { line += "  \(shortcut)" }
        if !node.children.isEmpty, node.role != "MenuBarItem" {
            line += "  >"
        }
        print(line)

        for child in node.children {
            printMenuItem(child, depth: depth + 1)
        }
    }
}

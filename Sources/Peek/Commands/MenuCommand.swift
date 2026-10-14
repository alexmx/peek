import AppKit
import ArgumentParser
import Foundation

struct MenuCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "menu",
        abstract: "Inspect the menu bar structure of an application"
    )

    @OptionGroup var target: WindowTarget

    @Option(
        name: .long,
        help: "Click a menu item by title (case-insensitive substring, exact match preferred) or full path ('File > Open Recent > Clear Menu'). Combine with --path to scope the search."
    )
    var click: String?

    @Option(name: .long, help: "Search for menu items by title (case-insensitive substring)")
    var find: String?

    @Option(
        name: .long,
        help: "Return only the submenu at this path (e.g. 'Debug' or 'Edit > Find'). With --click, scopes the click to this submenu."
    )
    var path: String?

    @Flag(name: .long, help: "Operate on the status-item (menu bar extra) bar instead of the main menu bar")
    var extras = false

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    struct ClickResult: Encodable {
        let title: String
        let path: String
    }

    func run() async throws {
        let pid = try await resolvePID()

        if let click {
            _ = try? await InteractionManager.activateApp(pid: pid)
            let clicked = try MenuBarManager.clickMenuItem(pid: pid, title: click, path: path, extras: extras)
            try emit(ClickResult(title: clicked.title, path: clicked.path), as: format) {
                print("Clicked menu item: \(clicked.path)")
            }
            return
        }

        if let find {
            let items = try MenuBarManager.findMenuItems(pid: pid, title: find, extras: extras)
            try emit(items, as: format) {
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

        let tree: MenuNode = if let path {
            try MenuBarManager.menuSubtree(pid: pid, path: path, extras: extras)
        } else {
            try MenuBarManager.menuBar(pid: pid, extras: extras)
        }

        try emit(tree, as: format) {
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

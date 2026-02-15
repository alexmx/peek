import ArgumentParser
import CoreGraphics
import Foundation

struct FindCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "find",
        abstract: "Search for UI elements by attributes or coordinates"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .long, help: "Filter by role (e.g. Button, StaticText)")
    var role: String?

    @Option(name: .long, help: "Filter by title (case-insensitive substring)")
    var title: String?

    @Option(name: .long, help: "Filter by value (case-insensitive substring)")
    var value: String?

    @Option(name: .long, help: "Filter by description (case-insensitive substring)")
    var desc: String?

    @Option(name: .long, help: "Hit-test X screen coordinate (use with --y)")
    var x: Int?

    @Option(name: .long, help: "Hit-test Y screen coordinate (use with --x)")
    var y: Int?

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func validate() throws {
        let hasFilters = role != nil || title != nil || value != nil || desc != nil
        let hasCoords = x != nil || y != nil

        if !hasFilters && !hasCoords {
            throw ValidationError("Provide --x/--y or at least one filter: --role, --title, --value, or --desc")
        }
        if hasFilters && hasCoords {
            throw ValidationError("--x/--y cannot be combined with --role, --title, --value, or --desc")
        }
        if hasCoords && (x == nil || y == nil) {
            throw ValidationError("Both --x and --y are required for hit-testing")
        }
    }

    func run() throws {
        let windowID = try target.resolve()
        guard let pid = WindowManager.pid(forWindowID: windowID) else {
            throw PeekError.windowNotFound(windowID)
        }

        if let x, let y {
            try runHitTest(pid: pid, windowID: windowID, x: x, y: y)
        } else {
            try runSearch(pid: pid, windowID: windowID)
        }
    }

    private func runHitTest(pid: pid_t, windowID: CGWindowID, x: Int, y: Int) throws {

        guard let node = try AccessibilityTreeManager.elementAt(
            pid: pid,
            windowID: windowID,
            x: x,
            y: y
        ) else {
            print("No element found at (\(x), \(y)).")
            return
        }

        if format == .json {
            try printJSON(node)
        } else {
            printNode(node)
        }
    }

    private func runSearch(pid: pid_t, windowID: CGWindowID) throws {
        let results = try AccessibilityTreeManager.find(
            pid: pid,
            windowID: windowID,
            role: role,
            title: title,
            value: value,
            description: desc
        )

        if format == .json {
            try printJSON(results)
        } else {
            if results.isEmpty {
                print("No matching elements found.")
            } else {
                for node in results {
                    printNode(node)
                }
                print("\n\(results.count) element(s) found.")
            }
        }
    }

    private func printNode(_ node: AXNode) {
        var line = node.role
        if let t = node.title, !t.isEmpty { line += "  \"\(t)\"" }
        if let v = node.value, !v.isEmpty { line += "  value=\"\(v)\"" }
        if let d = node.description, !d.isEmpty { line += "  desc=\"\(d)\"" }
        if let f = node.frame {
            line += "  (\(f.x), \(f.y)) \(f.width)x\(f.height)"
        }
        print(line)
    }
}

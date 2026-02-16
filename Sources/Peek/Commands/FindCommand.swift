import ArgumentParser
import CoreGraphics
import Foundation

struct FindCommand: AsyncParsableCommand {
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

    func run() async throws {
        let resolved = try await target.resolve()

        if let x, let y {
            try runHitTest(pid: resolved.pid, windowID: resolved.windowID, x: x, y: y)
        } else {
            try runSearch(pid: resolved.pid, windowID: resolved.windowID)
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

        switch format {
        case .json:
            try printJSON(node)
        case .toon:
            try printTOON(node)
        case .default:
            print(node.formatted)
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

        switch format {
        case .json:
            try printJSON(results)
        case .toon:
            try printTOON(results)
        case .default:
            if results.isEmpty {
                print("No matching elements found.")
            } else {
                for node in results {
                    print(node.formatted)
                }
                print("\n\(results.count) element(s) found.")
            }
        }
    }
}

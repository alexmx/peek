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

    @Option(name: .long, help: "Filter by enabled state (true → enabled only, false → disabled only)")
    var enabled: Bool?

    @Option(name: .long, help: "Hit-test X screen coordinate (use with --y)")
    var x: Int?

    @Option(name: .long, help: "Hit-test Y screen coordinate (use with --x)")
    var y: Int?

    @Option(name: .long, help: "Stop after this many matches (1 = first match; omit = all). Big speedup on deep trees.")
    var limit: Int?

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
        guard let node = try AccessibilityManager.elementAt(
            pid: pid,
            windowID: windowID,
            x: x,
            y: y
        ) else {
            print("No element found at (\(x), \(y)).")
            return
        }

        try emit(node, as: format) {
            print(node.formatted)
        }
    }

    private func runSearch(pid: pid_t, windowID: CGWindowID) throws {
        let results = try AccessibilityManager.find(
            pid: pid,
            windowID: windowID,
            role: role,
            title: title,
            value: value,
            description: desc,
            enabled: enabled,
            limit: limit
        )

        try emit(results, as: format) {
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

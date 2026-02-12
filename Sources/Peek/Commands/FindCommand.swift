import ArgumentParser
import CoreGraphics
import Foundation

struct FindCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "find",
        abstract: "Search for UI elements in a window"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .long, help: "Filter by role (e.g. AXButton, AXStaticText)")
    var role: String?

    @Option(name: .long, help: "Filter by title (case-insensitive substring)")
    var title: String?

    @Option(name: .long, help: "Filter by value (case-insensitive substring)")
    var value: String?

    @Option(name: .long, help: "Filter by description (case-insensitive substring)")
    var desc: String?

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func validate() throws {
        if role == nil, title == nil, value == nil, desc == nil {
            throw ValidationError("At least one filter is required: --role, --title, --value, or --desc")
        }
    }

    func run() throws {
        let windowID = try target.resolve()
        guard let pid = WindowManager.pid(forWindowID: windowID) else {
            throw PeekError.windowNotFound(windowID)
        }

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
                    var line = node.role
                    if let t = node.title, !t.isEmpty { line += "  \"\(t)\"" }
                    if let v = node.value, !v.isEmpty { line += "  value=\"\(v)\"" }
                    if let d = node.description, !d.isEmpty { line += "  desc=\"\(d)\"" }
                    if let f = node.frame {
                        line += "  (\(f.x), \(f.y)) \(f.width)x\(f.height)"
                    }
                    print(line)
                }
                print("\n\(results.count) element(s) found.")
            }
        }
    }
}

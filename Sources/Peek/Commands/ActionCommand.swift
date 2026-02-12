import ArgumentParser
import CoreGraphics
import Foundation

struct ActionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "action",
        abstract: "Perform an accessibility action on a UI element"
    )

    @OptionGroup var target: WindowTarget

    @Argument(help: "The AX action to perform (e.g. AXPress, AXConfirm, AXCancel, AXShowMenu)")
    var action: String

    @Option(name: .long, help: "Filter by role (e.g. AXButton)")
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

        let node = try InteractionManager.performAction(
            pid: pid,
            windowID: windowID,
            action: action,
            role: role,
            title: title,
            value: value,
            description: desc
        )

        if format == .json {
            try printJSON(node)
        } else {
            var line = "Performed '\(action)' on: \(node.role)"
            if let t = node.title, !t.isEmpty { line += "  \"\(t)\"" }
            if let v = node.value, !v.isEmpty { line += "  value=\"\(v)\"" }
            if let d = node.description, !d.isEmpty { line += "  desc=\"\(d)\"" }
            print(line)
        }
    }
}

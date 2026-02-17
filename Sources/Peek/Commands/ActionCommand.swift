import ArgumentParser
import CoreGraphics
import Foundation

struct ActionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "action",
        abstract: "Perform an accessibility action on a UI element"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .long, help: "The action to perform (e.g. Press, Confirm, Cancel, ShowMenu)")
    var `do`: String

    @Option(name: .long, help: "Filter by role (e.g. Button)")
    var role: String?

    @Option(name: .long, help: "Filter by title (case-insensitive substring)")
    var title: String?

    @Option(name: .long, help: "Filter by value (case-insensitive substring)")
    var value: String?

    @Option(name: .long, help: "Filter by description (case-insensitive substring)")
    var desc: String?

    @Flag(name: .long, help: "Perform the action on all matching elements (default: first match only)")
    var all: Bool = false

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func validate() throws {
        if role == nil, title == nil, value == nil, desc == nil {
            throw ValidationError("At least one filter is required: --role, --title, --value, or --desc")
        }
    }

    func run() async throws {
        let resolved = try await target.resolve()

        let action = self.do

        if all {
            let nodes = try InteractionManager.performActionOnAll(
                pid: resolved.pid,
                windowID: resolved.windowID,
                action: action,
                role: role,
                title: title,
                value: value,
                description: desc
            )

            switch format {
            case .json:
                try printJSON(nodes)
            case .toon:
                try printTOON(nodes)
            case .default:
                for node in nodes {
                    print("Performed '\(AXBridge.stripAXPrefix(action))' on: \(node.formatted)")
                }
                print("\(nodes.count) element(s) affected.")
            }
        } else {
            let node = try InteractionManager.performAction(
                pid: resolved.pid,
                windowID: resolved.windowID,
                action: action,
                role: role,
                title: title,
                value: value,
                description: desc
            )

            switch format {
            case .json:
                try printJSON(node)
            case .toon:
                try printTOON(node)
            case .default:
                print("Performed '\(AXBridge.stripAXPrefix(action))' on: \(node.formatted)")
            }
        }
    }
}

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

    @Flag(name: .long, help: "Also return the accessibility tree after performing the action")
    var resultTree: Bool = false

    @Option(name: .long, help: "Tree depth limit when --result-tree is used")
    var depth: Int?

    @Option(name: .long, help: "Seconds to wait before capturing the tree (default: 1)")
    var delay: Double?

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

        let nodes: [AXNode] = if all {
            try InteractionManager.performActionOnAll(
                pid: resolved.pid, windowID: resolved.windowID, action: action,
                role: role, title: title, value: value, description: desc
            )
        } else {
            try [InteractionManager.performAction(
                pid: resolved.pid, windowID: resolved.windowID, action: action,
                role: role, title: title, value: value, description: desc
            )]
        }

        if resultTree {
            let settleDelay = delay ?? 1.0
            usleep(UInt32(settleDelay * 1_000_000))
            let treeNode = try AccessibilityManager.inspect(
                pid: resolved.pid, windowID: resolved.windowID, maxDepth: depth
            )
            switch format {
            case .json: try printJSON(ActionTreeResult(action: nodes, resultTree: treeNode))
            case .toon: try printTOON(ActionTreeResult(action: nodes, resultTree: treeNode))
            case .default:
                for node in nodes {
                    print("Performed '\(AXBridge.stripAXPrefix(action))' on: \(node.formatted)")
                }
            }
            return
        }

        switch format {
        case .json:
            if all { try printJSON(nodes) } else { try printJSON(nodes[0]) }
        case .toon:
            if all { try printTOON(nodes) } else { try printTOON(nodes[0]) }
        case .default:
            for node in nodes {
                print("Performed '\(AXBridge.stripAXPrefix(action))' on: \(node.formatted)")
            }
            if all { print("\(nodes.count) element(s) affected.") }
        }
    }
}

import ArgumentParser
import CoreGraphics
import Foundation

struct ActionCommand: AsyncParsableCommand {
    enum VerifyMode: String, ExpressibleByArgument {
        case none, tree, diff
    }

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

    @Option(
        name: .long,
        help: "Verification mode after the action: 'none' (default), 'tree' (post-action snapshot), 'diff' (only what changed)"
    )
    var verify: VerifyMode = .none

    @Option(name: .long, help: "Tree depth limit when --verify=tree or --verify=diff")
    var depth: Int?

    @Option(name: .long, help: "Seconds to wait before the post-action snapshot (default: 0.15)")
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
        let settleDelay = delay ?? 0.15

        let beforeFlat: [AXNode]? = if verify == .diff {
            try MonitorManager.flattenNodes(
                AccessibilityManager.inspect(pid: resolved.pid, windowID: resolved.windowID, maxDepth: depth)
            )
        } else {
            nil
        }

        let nodes: [AXNode] = if all {
            try await InteractionManager.performActionOnAll(
                pid: resolved.pid, windowID: resolved.windowID, action: action,
                role: role, title: title, value: value, description: desc
            )
        } else {
            try await [InteractionManager.performAction(
                pid: resolved.pid, windowID: resolved.windowID, action: action,
                role: role, title: title, value: value, description: desc
            )]
        }

        switch verify {
        case .tree:
            usleep(UInt32(settleDelay * 1_000_000))
            let treeNode = try AccessibilityManager.inspect(
                pid: resolved.pid, windowID: resolved.windowID, maxDepth: depth
            )
            try printActionResult(ActionTreeResult(action: nodes, resultTree: treeNode), nodes: nodes, action: action)
        case .diff:
            usleep(UInt32(settleDelay * 1_000_000))
            let afterTree = try AccessibilityManager.inspect(
                pid: resolved.pid, windowID: resolved.windowID, maxDepth: depth
            )
            let diff = MonitorManager.computeDiff(
                before: beforeFlat ?? [],
                after: MonitorManager.flattenNodes(afterTree)
            )
            try printActionResult(ActionDiffResult(action: nodes, diff: diff), nodes: nodes, action: action)
        case .none:
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

    private func printActionResult(_ result: some Encodable, nodes: [AXNode], action: String) throws {
        switch format {
        case .json: try printJSON(result)
        case .toon: try printTOON(result)
        case .default:
            for node in nodes {
                print("Performed '\(AXBridge.stripAXPrefix(action))' on: \(node.formatted)")
            }
        }
    }
}

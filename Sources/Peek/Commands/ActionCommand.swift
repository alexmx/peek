import ArgumentParser
import CoreGraphics
import Foundation

struct ActionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "action",
        abstract: "Perform an accessibility action on a UI element"
    )

    @OptionGroup var target: WindowTarget

    @Option(
        name: .long,
        help: "The action to perform (e.g. Press, Confirm, Cancel, ShowMenu, Select). Select sets AXSelected for rows/items (NSOutlineView/NSTableView) that have no AXPress."
    )
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
    var verify: ActionVerifyMode = .none

    @Option(name: .long, help: "Tree depth limit when --verify=tree or --verify=diff")
    var depth: Int?

    @Option(name: .long, help: "Seconds to wait before the post-action snapshot (default: 0.15)")
    var delay: Double?

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func validate() throws {
        if filter.isEmpty {
            throw ValidationError("At least one filter is required: --role, --title, --value, or --desc")
        }
    }

    private var filter: ElementFilter {
        ElementFilter(role: role, title: title, value: value, description: desc)
    }

    func run() async throws {
        let resolved = try await target.resolve()
        let outcome = try await InteractionManager.performAndVerify(
            pid: resolved.pid, windowID: resolved.windowID, action: self.do,
            filter: filter, all: all,
            verify: verify, depth: depth, settleDelay: delay ?? 0.15
        )

        try emit(outcome, as: format) {
            for node in outcome.nodes {
                print("Performed '\(AXBridge.stripAXPrefix(self.do))' on: \(node.formatted)")
            }
            if case .performed = outcome, all {
                print("\(outcome.nodes.count) element(s) affected.")
            }
        }
    }
}

extension ActionVerifyMode: ExpressibleByArgument {}

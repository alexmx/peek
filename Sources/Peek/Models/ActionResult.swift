import Foundation

/// What `action` captures after performing: nothing, the post-action tree, or a before/after diff.
enum ActionVerifyMode: String, LenientStringEnum {
    case none, tree, diff
}

struct ActionTreeResult: Encodable {
    let action: [AXNode]
    let resultTree: AXNode
}

struct ActionDiffResult: Encodable {
    let action: [AXNode]
    let diff: TreeDiff
}

/// Result of `InteractionManager.performAndVerify`, shaped by the verify mode.
enum ActionOutcome: Encodable {
    /// No verification. `all == false` encodes the single matched node, not an array.
    case performed([AXNode], all: Bool)
    case tree(ActionTreeResult)
    case diff(ActionDiffResult)

    /// The nodes the action was performed on.
    var nodes: [AXNode] {
        switch self {
        case let .performed(nodes, _): nodes
        case let .tree(result): result.action
        case let .diff(result): result.action
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .performed(nodes, all):
            if all { try container.encode(nodes) } else { try container.encode(nodes[0]) }
        case let .tree(result):
            try container.encode(result)
        case let .diff(result):
            try container.encode(result)
        }
    }
}

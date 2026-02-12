import Foundation

struct TreeDiff: Encodable {
    let added: [AXNode]
    let removed: [AXNode]
    let changed: [NodeChange]

    struct NodeChange: Encodable {
        let identity: String
        let role: String
        let before: ChangeValues
        let after: ChangeValues
    }

    struct ChangeValues: Encodable {
        let title: String?
        let value: String?
        let description: String?
        let frame: AXNode.FrameInfo?
    }
}

import Foundation

struct ActionTreeResult: Encodable {
    let action: [AXNode]
    let resultTree: AXNode
}

struct ActionDiffResult: Encodable {
    let action: [AXNode]
    let diff: TreeDiff
}

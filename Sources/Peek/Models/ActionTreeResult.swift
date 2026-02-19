import Foundation

struct ActionTreeResult: Encodable {
    let action: [AXNode]
    let resultTree: AXNode
}

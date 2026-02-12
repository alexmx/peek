import Foundation

struct MenuNode: Encodable {
    let title: String
    let role: String
    let enabled: Bool
    let shortcut: String?
    let children: [MenuNode]
}

import Foundation

struct MenuNode: Encodable {
    let title: String
    let role: String
    let enabled: Bool
    let shortcut: String?
    let path: String?
    let children: [MenuNode]

    init(title: String, role: String, enabled: Bool, shortcut: String?, path: String? = nil, children: [MenuNode]) {
        self.title = title
        self.role = role
        self.enabled = enabled
        self.shortcut = shortcut
        self.path = path
        self.children = children
    }

    /// Copy without children and with a menu path, for flat search results.
    func withPath(_ path: String) -> MenuNode {
        MenuNode(title: title, role: role, enabled: enabled, shortcut: shortcut, path: path, children: [])
    }
}

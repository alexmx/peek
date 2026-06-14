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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !title.isEmpty {
            try container.encode(title, forKey: .title)
        }
        try container.encode(role, forKey: .role)
        if !enabled {
            try container.encode(false, forKey: .enabled)
        }
        try container.encodeIfPresent(shortcut, forKey: .shortcut)
        try container.encodeIfPresent(path, forKey: .path)
        if !children.isEmpty {
            try container.encode(children, forKey: .children)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case title, role, enabled, shortcut, path, children
    }

    /// Copy without children and with a menu path, for flat search results.
    func withPath(_ path: String) -> MenuNode {
        MenuNode(title: title, role: role, enabled: enabled, shortcut: shortcut, path: path, children: [])
    }

    /// Return a copy pruned to the given depth (root = 0). Children beyond the limit
    /// are dropped entirely.
    func pruned(toDepth limit: Int, current: Int = 0) -> MenuNode {
        let nextChildren = current >= limit
            ? []
            : children.map { $0.pruned(toDepth: limit, current: current + 1) }
        return MenuNode(
            title: title,
            role: role,
            enabled: enabled,
            shortcut: shortcut,
            path: path,
            children: nextChildren
        )
    }
}

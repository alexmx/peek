import Foundation

struct AXNode: Encodable, Equatable {
    let role: String
    let title: String?
    let value: String?
    let description: String?
    let frame: FrameInfo?
    let children: [AXNode]

    struct FrameInfo: Encodable, Equatable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    /// Single-line text representation: `Role  "title"  value="val"  desc="desc"  (x, y) WxH`
    var formatted: String {
        var line = role
        if let t = title, !t.isEmpty { line += "  \"\(t)\"" }
        if let v = value, !v.isEmpty { line += "  value=\"\(v)\"" }
        if let d = description, !d.isEmpty { line += "  desc=\"\(d)\"" }
        if let f = frame {
            line += "  (\(f.x), \(f.y)) \(f.width)x\(f.height)"
        }
        return line
    }

    /// Check if this node matches the given filters.
    func matches(role: String?, title: String?, value: String?, description: String?) -> Bool {
        if let role, self.role != role { return false }
        if let title, self.title?.localizedCaseInsensitiveContains(title) != true { return false }
        if let value, self.value?.localizedCaseInsensitiveContains(value) != true { return false }
        if let description, self.description?.localizedCaseInsensitiveContains(description) != true { return false }
        return true
    }

    /// Copy of this node without children (for flat result lists).
    var withoutChildren: AXNode {
        AXNode(role: role, title: title, value: value, description: description, frame: frame, children: [])
    }

    /// A unique-ish identity for diffing: role + title + description + frame position.
    var identity: String {
        let parts = [role, title ?? "", description ?? ""]
        if let f = frame {
            return parts.joined(separator: "|") + "|\(f.x),\(f.y)"
        }
        return parts.joined(separator: "|")
    }
}

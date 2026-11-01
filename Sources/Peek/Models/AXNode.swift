import Foundation

struct AXNode: Encodable, Equatable {
    let role: String
    let title: String?
    let value: String?
    let description: String?
    let enabled: Bool?
    let frame: FrameInfo?
    let children: [AXNode]
    /// Set when `value` is a capped preview of parameterized text (AXStringForRange).
    /// `valueLength` is the full character count; fetch the rest with `peek text`.
    let valueTruncated: Bool?
    let valueLength: Int?

    struct FrameInfo: Encodable, Equatable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    init(
        role: String,
        title: String?,
        value: String?,
        description: String?,
        enabled: Bool?,
        frame: FrameInfo?,
        children: [AXNode],
        valueTruncated: Bool? = nil,
        valueLength: Int? = nil
    ) {
        self.role = role
        self.title = title
        self.value = value
        self.description = description
        self.enabled = enabled
        self.frame = frame
        self.children = children
        self.valueTruncated = valueTruncated
        self.valueLength = valueLength
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(description, forKey: .description)
        if enabled == false {
            try container.encode(false, forKey: .enabled)
        }
        if let frame, frame.x != 0 || frame.y != 0 || frame.width != 0 || frame.height != 0 {
            try container.encode(frame, forKey: .frame)
        }
        if valueTruncated == true {
            try container.encode(true, forKey: .valueTruncated)
            try container.encodeIfPresent(valueLength, forKey: .valueLength)
        }
        if !children.isEmpty {
            try container.encode(children, forKey: .children)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case role, title, value, description, enabled, frame, children, valueTruncated, valueLength
    }

    /// Single-line text representation: `Role  "title"  value="val"  desc="desc"  (x, y) WxH`
    var formatted: String {
        var line = role
        if let t = title, !t.isEmpty { line += "  \"\(t)\"" }
        if let v = value, !v.isEmpty { line += "  value=\"\(v)\"" }
        if valueTruncated == true,
           let n = valueLength { line += "  (+\(n - (value?.count ?? 0)) more chars; peek text)" }
        if let d = description, !d.isEmpty { line += "  desc=\"\(d)\"" }
        if enabled == false { line += "  (disabled)" }
        if let f = frame {
            line += "  (\(f.x), \(f.y)) \(f.width)x\(f.height)"
        }
        return line
    }

    /// Copy of this node without children (for flat result lists).
    var withoutChildren: AXNode {
        AXNode(
            role: role,
            title: title,
            value: value,
            description: description,
            enabled: enabled,
            frame: frame,
            children: [],
            valueTruncated: valueTruncated,
            valueLength: valueLength
        )
    }

    /// This node and all its descendants, depth-first, each without children.
    var flattened: [AXNode] {
        [withoutChildren] + children.flatMap(\.flattened)
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

extension AXNode.FrameInfo {
    /// Integer frame from a CGRect (each component truncated toward zero).
    init(_ rect: CGRect) {
        self.init(
            x: Int(rect.origin.x),
            y: Int(rect.origin.y),
            width: Int(rect.size.width),
            height: Int(rect.size.height)
        )
    }
}

import Foundation

/// Attribute filters for element search. `role` matches exactly (with or without the "AX"
/// prefix); `title`, `value` and `description` are case-insensitive substrings, and `title`
/// matches AXTitle OR AXDescription. Nil filters match anything.
struct ElementFilter {
    /// Stored without the "AX" prefix.
    let role: String?
    let title: String?
    let value: String?
    let description: String?
    let enabled: Bool?

    init(
        role: String? = nil,
        title: String? = nil,
        value: String? = nil,
        description: String? = nil,
        enabled: Bool? = nil
    ) {
        self.role = role.map(AXBridge.stripAXPrefix)
        self.title = title
        self.value = value
        self.description = description
        self.enabled = enabled
    }

    /// True when no role/title/value/description filter is set. `enabled` alone only
    /// narrows a search, so it doesn't count.
    var isEmpty: Bool {
        role == nil && title == nil && value == nil && description == nil
    }

    /// The matching rules. Each attribute is read through its closure only when a filter
    /// needs it, in that order, stopping at the first mismatch — so the live AX path
    /// (`AXBridge.elementMatches`) only pays for the attributes it checks. `role` must be
    /// supplied without the "AX" prefix; a missing `enabled` counts as enabled.
    func matches(
        role readRole: () -> String?,
        title readTitle: () -> String?,
        value readValue: () -> String?,
        description readDescription: () -> String?,
        enabled readEnabled: () -> Bool?
    ) -> Bool {
        if let role, readRole() != role { return false }
        if let title,
           readTitle()?.localizedCaseInsensitiveContains(title) != true,
           readDescription()?.localizedCaseInsensitiveContains(title) != true {
            return false
        }
        if let value, readValue()?.localizedCaseInsensitiveContains(value) != true { return false }
        if let description, readDescription()?.localizedCaseInsensitiveContains(description) != true { return false }
        if let enabled, (readEnabled() ?? true) != enabled { return false }
        return true
    }

    /// Match against an already-read node snapshot.
    func matches(_ node: AXNode) -> Bool {
        matches(
            role: { node.role },
            title: { node.title },
            value: { node.value },
            description: { node.description },
            enabled: { node.enabled }
        )
    }
}

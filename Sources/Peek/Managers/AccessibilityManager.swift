import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// High-level accessibility operations: window/menu bar resolution, tree building, and element search.
enum AccessibilityManager {
    static let maxDepth = 50

    // MARK: - Resolution

    /// Resolve a window element, activating the app and retrying if needed.
    ///
    /// `windowID == 0` is a sentinel meaning "this app has no AXWindow" — the AXApplication
    /// element is returned instead. Used for window-less system UI (Dock, Control Center,
    /// Notification Center, menu-bar status items) whose AX tree is rooted directly on the
    /// application element with no intermediate window.
    static func resolveWindow(pid: pid_t, windowID: CGWindowID) throws -> AXUIElement {
        try PermissionManager.requireAccessibility()

        if windowID == 0 {
            return AXBridge.application(pid: pid)
        }

        if let w = AXBridge.window(pid: pid, windowID: windowID) {
            return w
        }

        // AX tree inaccessible — app may be on another Space. Activate and retry.
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            throw PeekError.noWindows
        }
        app.activate()

        // Sync on purpose: rare off-Space retry; the common path returns above without
        // sleeping. Going async would ripple through the whole sync AX-read call graph.
        for _ in 0..<20 {
            Delay.blockingMilliseconds(100)
            if let w = AXBridge.window(pid: pid, windowID: windowID) {
                return w
            }
        }

        throw PeekError.noWindows
    }

    /// Get the menu bar element for an application, activating if needed.
    static func menuBar(pid: pid_t) throws -> AXUIElement {
        try PermissionManager.requireAccessibility()

        let app = AXBridge.application(pid: pid)

        func fetchMenuBar() -> AXUIElement? {
            var ref: AnyObject?
            guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &ref) == .success,
                  let ref else {
                return nil
            }
            // swiftlint:disable:next force_cast
            return (ref as! AXUIElement)
        }

        if let bar = fetchMenuBar() { return bar }

        // Menu bar not accessible — app may be on another Space. Activate and retry.
        guard let runningApp = NSRunningApplication(processIdentifier: pid) else {
            throw PeekError.noMenuBar(pid)
        }
        runningApp.activate()

        // Sync on purpose — see resolveWindow: rare off-Space retry path.
        for _ in 0..<20 {
            Delay.blockingMilliseconds(100)
            if let bar = fetchMenuBar() { return bar }
        }

        throw PeekError.noMenuBar(pid)
    }

    // MARK: - Tree Building

    /// Recursively build a full AXNode tree from an element.
    static func buildTree(from element: AXUIElement, depth: Int = 0, limit: Int = maxDepth) -> AXNode {
        let base = AXBridge.nodeFromElement(element)

        var childNodes: [AXNode] = []
        if depth < limit, let children = AXBridge.children(of: element) {
            childNodes = children.map { buildTree(from: $0, depth: depth + 1, limit: limit) }
        }

        return AXNode(
            role: base.role,
            title: base.title,
            value: base.value,
            description: base.description,
            enabled: base.enabled,
            frame: base.frame,
            children: childNodes
        )
    }

    // MARK: - Inspection

    static func inspect(pid: pid_t, windowID: CGWindowID, maxDepth: Int? = nil) throws -> AXNode {
        let window = try resolveWindow(pid: pid, windowID: windowID)
        return buildTree(from: window, depth: 0, limit: maxDepth ?? Self.maxDepth)
    }

    // MARK: - Element Search

    /// A found element: the live AXUIElement reference plus its AXNode snapshot.
    struct ElementMatch {
        let ref: AXUIElement
        let node: AXNode
    }

    /// Search the tree for nodes matching the given criteria.
    static func find(
        pid: pid_t,
        windowID: CGWindowID,
        role: String?,
        title: String?,
        value: String?,
        description: String?,
        enabled: Bool? = nil,
        limit: Int? = nil
    ) throws -> [AXNode] {
        let window = try resolveWindow(pid: pid, windowID: windowID)
        return findAll(
            in: window, role: role, title: title, value: value,
            description: description, enabled: enabled, limit: limit
        ).map(\.node)
    }

    /// A range of text read from an element via parameterized AX attributes.
    /// `bounds` is the screen rect of the returned range when requested (and supported).
    /// `selection` is the element's live caret/selection when requested (and supported),
    /// independent of the read range.
    struct TextContent: Encodable {
        let length: Int
        let offset: Int
        let text: String
        let truncated: Bool
        let bounds: AXNode.FrameInfo?
        let selection: Selection?
    }

    /// The current caret/selection of a text element (length 0 = caret position).
    struct Selection: Encodable {
        let offset: Int
        let length: Int
    }

    /// Default character ceiling for a single `readText` call.
    static let textReadCap = 20000

    /// Read text from the first element matching the filters, paging via offset/length.
    /// Reads `AXStringForRange` so it returns content that lives behind parameterized
    /// attributes (e.g. SwiftUI static text) where `AXValue` is empty. When `bounds`
    /// is true, also returns the screen rect of the returned range (AXBoundsForRange)
    /// for feeding peek_click/peek_drag — pair it with a small explicit offset/length.
    ///
    /// When `substring` is given, locate its first occurrence at or after `offset`
    /// (case-sensitive) and return that match's range instead of a positional read —
    /// `length` is ignored. Advance `offset` past a match to page through occurrences.
    static func readText(
        pid: pid_t,
        windowID: CGWindowID,
        role: String?,
        title: String?,
        value: String?,
        description: String?,
        offset: Int,
        length: Int?,
        bounds: Bool = false,
        selection: Bool = false,
        substring: String? = nil
    ) throws -> TextContent {
        let window = try resolveWindow(pid: pid, windowID: windowID)
        guard let match = findFirst(
            in: window, role: role, title: title, value: value, description: description
        ) else {
            throw PeekError.elementNotFound
        }
        guard let total = AXBridge.numberOfCharacters(of: match.ref) else {
            throw PeekError.noTextContent
        }
        // Selection is element state, independent of the read range.
        let sel = selection ? AXBridge.selectedRange(of: match.ref).map {
            Selection(offset: $0.offset, length: $0.length)
        } : nil
        let start = max(0, offset)

        if let substring {
            return try locate(
                substring, in: match.ref, total: total, from: start, bounds: bounds, selection: sel
            )
        }

        if start >= total {
            return TextContent(length: total, offset: start, text: "", truncated: false, bounds: nil, selection: sel)
        }
        let take = min(length ?? textReadCap, total - start)
        guard let text = AXBridge.string(of: match.ref, offset: start, length: take) else {
            throw PeekError.noTextContent
        }
        let rect = bounds ? boundsInfo(of: match.ref, offset: start, length: take) : nil
        return TextContent(
            length: total, offset: start, text: text,
            truncated: start + take < total, bounds: rect, selection: sel
        )
    }

    /// Find `needle`'s first occurrence at or after `from` and return its range.
    /// Uses NSString (UTF-16) indexing so offsets line up with AX character ranges.
    private static func locate(
        _ needle: String,
        in ref: AXUIElement,
        total: Int,
        from: Int,
        bounds: Bool,
        selection: Selection?
    ) throws -> TextContent {
        guard from < total,
              let hay = AXBridge.string(of: ref, offset: from, length: total - from),
              let matchOffset = firstOccurrence(of: needle, in: hay, from: from)
        else {
            throw PeekError.substringNotFound(needle)
        }
        let rect = bounds ? boundsInfo(of: ref, offset: matchOffset, length: (needle as NSString).length) : nil
        return TextContent(
            length: total, offset: matchOffset, text: needle,
            truncated: false, bounds: rect, selection: selection
        )
    }

    /// Absolute offset of `needle`'s first occurrence in `haystack`, where `haystack`
    /// was read starting at `base`. Uses NSString (UTF-16) indexing so the result lines
    /// up with AX character ranges — Swift's native `String` indexing would miscount any
    /// non-BMP characters (emoji, surrogate-pair CJK) and break AXBoundsForRange.
    static func firstOccurrence(of needle: String, in haystack: String, from base: Int) -> Int? {
        let range = (haystack as NSString).range(of: needle)
        guard range.location != NSNotFound else { return nil }
        return base + range.location
    }

    private static func boundsInfo(of ref: AXUIElement, offset: Int, length: Int) -> AXNode.FrameInfo? {
        AXBridge.bounds(of: ref, offset: offset, length: length).map {
            AXNode.FrameInfo(
                x: Int($0.origin.x),
                y: Int($0.origin.y),
                width: Int($0.size.width),
                height: Int($0.size.height)
            )
        }
    }

    /// Find the deepest element at the given screen coordinates.
    static func elementAt(
        pid: pid_t,
        windowID: CGWindowID,
        x: Int,
        y: Int
    ) throws -> AXNode? {
        let window = try resolveWindow(pid: pid, windowID: windowID)
        let tree = buildTree(from: window, depth: 0)
        return deepestNode(in: tree, x: x, y: y)
    }

    /// System-wide hit-test: returns the topmost AXNode at a screen point across any app or
    /// layer. Used by `peek_move` to identify what the cursor is hovering, including elements
    /// in apps not addressable by window (Dock, menu bar, status items). Returns nil if no
    /// element is reported under the point — common over empty desktop / wallpaper.
    ///
    /// The returned node has `value` stripped: hover-target identification needs role/title/
    /// description/frame, not the full text content of a hovered TextArea (which can be
    /// kilobytes of unrelated text).
    static func elementAtScreenPoint(x: CGFloat, y: CGFloat) throws -> AXNode? {
        try PermissionManager.requireAccessibility()
        guard let element = AXBridge.elementAtSystemWide(x: x, y: y) else { return nil }
        let node = AXBridge.nodeFromElement(element)
        return AXNode(
            role: node.role,
            title: node.title,
            value: nil,
            description: node.description,
            enabled: node.enabled,
            frame: node.frame,
            children: []
        )
    }

    /// DFS to find the first element matching filters.
    static func findFirst(
        in element: AXUIElement,
        role: String?,
        title: String?,
        value: String?,
        description: String?
    ) -> ElementMatch? {
        searchFirst(
            in: element,
            role: role.map(AXBridge.stripAXPrefix),
            title: title,
            value: value,
            description: description,
            depth: 0
        )
    }

    /// DFS to find all elements matching filters.
    static func findAll(
        in element: AXUIElement,
        role: String?,
        title: String?,
        value: String?,
        description: String?,
        enabled: Bool? = nil,
        limit: Int? = nil
    ) -> [ElementMatch] {
        var results: [ElementMatch] = []
        searchAll(
            in: element,
            role: role.map(AXBridge.stripAXPrefix),
            title: title,
            value: value,
            description: description,
            enabled: enabled,
            limit: limit,
            depth: 0,
            results: &results
        )
        return results
    }

    // MARK: - Private Search

    private static func searchFirst(
        in element: AXUIElement,
        role: String?,
        title: String?,
        value: String?,
        description: String?,
        depth: Int
    ) -> ElementMatch? {
        guard depth < maxDepth else { return nil }

        if AXBridge.elementMatches(
            element, role: role, title: title, value: value, description: description, enabled: nil
        ) {
            return ElementMatch(ref: element, node: AXBridge.nodeFromElement(element))
        }

        if let children = AXBridge.children(of: element) {
            for child in children {
                if let found = searchFirst(
                    in: child,
                    role: role,
                    title: title,
                    value: value,
                    description: description,
                    depth: depth + 1
                ) {
                    return found
                }
            }
        }

        return nil
    }

    private static func searchAll(
        in element: AXUIElement,
        role: String?,
        title: String?,
        value: String?,
        description: String?,
        enabled: Bool?,
        limit: Int?,
        depth: Int,
        results: inout [ElementMatch]
    ) {
        guard depth < maxDepth else { return }
        if let limit, results.count >= limit { return }

        if AXBridge.elementMatches(
            element, role: role, title: title, value: value, description: description, enabled: enabled
        ) {
            results.append(ElementMatch(ref: element, node: AXBridge.nodeFromElement(element)))
            if let limit, results.count >= limit { return }
        }

        if let children = AXBridge.children(of: element) {
            for child in children {
                searchAll(
                    in: child,
                    role: role,
                    title: title,
                    value: value,
                    description: description,
                    enabled: enabled,
                    limit: limit,
                    depth: depth + 1,
                    results: &results
                )
                if let limit, results.count >= limit { return }
            }
        }
    }

    // MARK: - Hit Testing

    /// Find the deepest node containing the given point.
    static func deepestNode(in node: AXNode, x: Int, y: Int) -> AXNode? {
        guard let f = node.frame,
              x >= f.x, x < f.x + f.width,
              y >= f.y, y < f.y + f.height
        else { return nil }

        for child in node.children {
            if let deeper = deepestNode(in: child, x: x, y: y) {
                return deeper
            }
        }

        return node.withoutChildren
    }
}

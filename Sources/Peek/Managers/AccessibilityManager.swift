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

        guard let window = retryAfterActivating(pid: pid, fetch: { AXBridge.window(pid: pid, windowID: windowID) })
        else { throw PeekError.windowNotAccessible(windowID) }
        return window
    }

    /// Get the main menu bar element for an application, activating if needed.
    static func menuBar(pid: pid_t) throws -> AXUIElement {
        try menuBarElement(pid: pid, attribute: kAXMenuBarAttribute, missing: PeekError.noMenuBar(pid))
    }

    /// Get the "extras" menu bar — the status-item bar hosting NSStatusItem /
    /// SwiftUI MenuBarExtra items. Lives on the app's AXApplication under a separate
    /// attribute from the main menu bar, so it needs its own fetch.
    static func extrasMenuBar(pid: pid_t) throws -> AXUIElement {
        try menuBarElement(pid: pid, attribute: kAXExtrasMenuBarAttribute, missing: PeekError.noExtrasMenuBar(pid))
    }

    /// Copy a menu-bar-style attribute off the AXApplication, activating and
    /// retrying if the first fetch fails.
    private static func menuBarElement(
        pid: pid_t,
        attribute: String,
        missing: @autoclosure () -> PeekError
    ) throws -> AXUIElement {
        try PermissionManager.requireAccessibility()

        let app = AXBridge.application(pid: pid)
        let bar: AXUIElement? = retryAfterActivating(pid: pid) {
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, attribute as CFString, &ref) == .success,
                  let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
            // swiftlint:disable:next force_cast
            return (ref as! AXUIElement)
        }
        guard let bar else { throw missing() }
        return bar
    }

    /// Run `fetch`; if it fails — typically because the app is on another Space and its
    /// AX tree is inaccessible — activate the app and retry for up to 2s. Returns nil if
    /// the app isn't running or `fetch` never succeeds.
    ///
    /// Sync on purpose: a rare off-Space path; the common case returns on the first fetch
    /// without sleeping. Going async would ripple through the whole sync AX-read call graph.
    private static func retryAfterActivating<T>(pid: pid_t, fetch: () -> T?) -> T? {
        if let value = fetch() { return value }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        app.activate()
        for _ in 0..<20 {
            Delay.blockingMilliseconds(100)
            if let value = fetch() { return value }
        }
        return nil
    }

    // MARK: - Tree Building

    /// Recursively build a full AXNode tree from an element.
    static func buildTree(from element: AXUIElement, depth: Int = 0, limit: Int = maxDepth) -> AXNode {
        var walk = Walk(root: element)
        return buildTree(from: element, correction: nil, depth: depth, limit: limit, walk: &walk)
    }

    private static func buildTree(
        from element: AXUIElement,
        correction: TouchHost.FrameCorrection?,
        depth: Int,
        limit: Int,
        walk: inout Walk
    ) -> AXNode {
        let base = AXBridge.nodeFromElement(element, correcting: correction)

        var childNodes: [AXNode] = []
        if depth < limit {
            let children = walk.children(of: element, correction: correction)
            for child in children.elements where walk.enter(child) {
                childNodes.append(buildTree(
                    from: child, correction: children.correction, depth: depth + 1, limit: limit, walk: &walk
                ))
            }
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
    /// `frameCorrection` is set inside Device Hub's rotated iOS content; it maps other
    /// rects read off `ref` (text bounds) onto the screen the way `node.frame` already is.
    struct ElementMatch {
        let ref: AXUIElement
        let node: AXNode
        let frameCorrection: TouchHost.FrameCorrection?
    }

    /// Search the tree for nodes matching `filter`.
    static func find(pid: pid_t, windowID: CGWindowID, filter: ElementFilter, limit: Int? = nil) throws -> [AXNode] {
        let window = try resolveWindow(pid: pid, windowID: windowID)
        return findAll(in: window, filter: filter, limit: limit).map(\.node)
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
        filter: ElementFilter,
        offset: Int,
        length: Int?,
        bounds: Bool = false,
        selection: Bool = false,
        substring: String? = nil
    ) throws -> TextContent {
        let window = try resolveWindow(pid: pid, windowID: windowID)
        guard let match = findAll(in: window, filter: filter, limit: 1).first else {
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
                substring, in: match, total: total, from: start, bounds: bounds, selection: sel
            )
        }

        if start >= total {
            return TextContent(length: total, offset: start, text: "", truncated: false, bounds: nil, selection: sel)
        }
        let take = min(length ?? textReadCap, total - start)
        guard let text = AXBridge.string(of: match.ref, offset: start, length: take) else {
            throw PeekError.noTextContent
        }
        let rect = bounds ? boundsInfo(of: match, offset: start, length: take) : nil
        return TextContent(
            length: total, offset: start, text: text,
            truncated: start + take < total, bounds: rect, selection: sel
        )
    }

    /// Find `needle`'s first occurrence at or after `from` and return its range.
    /// Uses NSString (UTF-16) indexing so offsets line up with AX character ranges.
    private static func locate(
        _ needle: String,
        in match: ElementMatch,
        total: Int,
        from: Int,
        bounds: Bool,
        selection: Selection?
    ) throws -> TextContent {
        guard from < total,
              let hay = AXBridge.string(of: match.ref, offset: from, length: total - from),
              let matchOffset = firstOccurrence(of: needle, in: hay, from: from)
        else {
            throw PeekError.substringNotFound(needle)
        }
        let rect = bounds ? boundsInfo(of: match, offset: matchOffset, length: (needle as NSString).length) : nil
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

    private static func boundsInfo(of match: ElementMatch, offset: Int, length: Int) -> AXNode.FrameInfo? {
        AXBridge.bounds(of: match.ref, offset: offset, length: length).map {
            AXNode.FrameInfo(match.frameCorrection?.apply($0) ?? $0)
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

    /// DFS for elements matching `filter`, stopping after `limit` matches.
    static func findAll(in element: AXUIElement, filter: ElementFilter, limit: Int? = nil) -> [ElementMatch] {
        var results: [ElementMatch] = []
        var walk = Walk(root: element)
        searchAll(in: element, correction: nil, filter: filter, limit: limit, depth: 0, walk: &walk, results: &results)
        return results
    }

    // MARK: - Private Search

    private static func searchAll(
        in element: AXUIElement,
        correction: TouchHost.FrameCorrection?,
        filter: ElementFilter,
        limit: Int?,
        depth: Int,
        walk: inout Walk,
        results: inout [ElementMatch]
    ) {
        guard depth < maxDepth else { return }
        if let limit, results.count >= limit { return }

        if AXBridge.elementMatches(element, filter) {
            let node = AXBridge.nodeFromElement(element, correcting: correction)
            results.append(ElementMatch(ref: element, node: node, frameCorrection: correction))
            if let limit, results.count >= limit { return }
        }

        let children = walk.children(of: element, correction: correction)
        for child in children.elements where walk.enter(child) {
            searchAll(
                in: child, correction: children.correction, filter: filter, limit: limit,
                depth: depth + 1, walk: &walk, results: &results
            )
            if let limit, results.count >= limit { return }
        }
    }

    // MARK: - Walk

    /// State for one depth-first walk, shared by tree building and search.
    private struct Walk {
        /// Elements already reached. Device Hub lists its iOS content group under two
        /// parents; without this, everything inside it would be reported twice.
        private var visited: Set<AXUIElement>
        /// Only touch hosts can hold Device Hub's iOS content, so other apps skip the
        /// subrole read per element.
        private let detectsIOSContent: Bool

        init(root: AXUIElement) {
            self.visited = [root]
            var pid: pid_t = 0
            AXUIElementGetPid(root, &pid)
            self.detectsIOSContent = TouchHost.owns(pid: pid)
        }

        /// Mark `element` reached on the way down; false if the walk reached it before.
        /// Marking on entry (not when listing siblings) keeps a shared subtree under the
        /// first parent the walk descends into. Otherwise that parent is left empty, and
        /// hit-testing (which follows the first child containing the point) stops there.
        mutating func enter(_ element: AXUIElement) -> Bool {
            visited.insert(element).inserted
        }

        /// The children of `element`, and the frame correction for their subtrees: a new one
        /// below Device Hub's iOS content group, else `correction`.
        func children(
            of element: AXUIElement,
            correction: TouchHost.FrameCorrection?
        ) -> (elements: [AXUIElement], correction: TouchHost.FrameCorrection?) {
            guard let children = AXBridge.children(of: element), !children.isEmpty else { return ([], correction) }
            guard detectsIOSContent,
                  let iOSContent = TouchHost.FrameCorrection.detect(contentGroup: element, children: children)
            else { return (children, correction) }
            return (children, iOSContent)
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

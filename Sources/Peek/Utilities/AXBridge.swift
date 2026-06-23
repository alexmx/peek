import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Low-level bridge to the macOS Accessibility API.
enum AXBridge {
    // MARK: - Role Helpers

    /// Strip the "AX" prefix from a role name for display (e.g. "AXButton" → "Button").
    static func stripAXPrefix(_ role: String) -> String {
        role.hasPrefix("AX") ? String(role.dropFirst(2)) : role
    }

    /// Ensure a role has the "AX" prefix for AX API comparison (e.g. "Button" → "AXButton").
    static func ensureAXPrefix(_ role: String) -> String {
        role.hasPrefix("AX") ? role : "AX\(role)"
    }

    // MARK: - Attribute Helpers

    static func title(of element: AXUIElement) -> String? {
        string(of: element, key: kAXTitleAttribute)
    }

    private static func string(of element: AXUIElement, key: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &ref) == .success,
              let value = ref else { return nil }
        if let str = value as? String { return str }
        if let num = value as? NSNumber { return num.stringValue }
        return nil
    }

    private static func bool(of element: AXUIElement, key: String) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &ref) == .success,
              let value = ref else { return nil }
        if let num = value as? NSNumber { return num.boolValue }
        return nil
    }

    static func children(of element: AXUIElement) -> [AXUIElement]? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let children = ref as? [AXUIElement] else { return nil }
        return children
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var frameRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &frameRef) == .success,
           let frameRef, CFGetTypeID(frameRef) == AXValueGetTypeID() {
            var rect = CGRect.zero
            if AXValueGetValue(frameRef as! AXValue, .cgRect, &rect) {
                return rect
            }
        }

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              CFGetTypeID(posRef!) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef!) == AXValueGetTypeID()
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }

        return CGRect(origin: point, size: size)
    }

    private static func frameInfo(of element: AXUIElement) -> AXNode.FrameInfo? {
        frame(of: element).map {
            AXNode.FrameInfo(
                x: Int($0.origin.x),
                y: Int($0.origin.y),
                width: Int($0.size.width),
                height: Int($0.size.height)
            )
        }
    }

    // MARK: - Application

    /// Create an AXUIElement for an application by PID.
    static func application(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    /// System-wide hit-test: returns the topmost AX element at a screen point regardless of
    /// owning process. Used to identify what's under the cursor across any app or layer
    /// (Dock, menu bar, status items, popovers) without scoping to a known window or pid.
    static func elementAtSystemWide(x: CGFloat, y: CGFloat) -> AXUIElement? {
        let sysWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(sysWide, Float(x), Float(y), &element)
        guard result == .success else { return nil }
        return element
    }

    static func prewarm(pid: pid_t) {
        var ref: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(application(pid: pid), kAXWindowsAttribute as CFString, &ref)
    }

    /// Get the AXUIElement for a specific window by CGWindowID.
    /// Returns nil if the AX tree is inaccessible (e.g. app on another Space).
    static func window(pid: pid_t, windowID: CGWindowID) -> AXUIElement? {
        let appElement = application(pid: pid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            return nil
        }
        return windows.first { win in
            var id: CGWindowID = 0
            return _AXUIElementGetWindow(win, &id) == .success && id == windowID
        } ?? windows[0]
    }

    // MARK: - Node Extraction

    nonisolated(unsafe) private static let nodeAttributeKeys: CFArray = [
        kAXRoleAttribute,
        kAXTitleAttribute,
        kAXValueAttribute,
        kAXDescriptionAttribute,
        kAXEnabledAttribute,
        "AXFrame"
    ] as CFArray

    /// Read all standard attributes from an element and produce an AXNode (no children).
    /// Batches the six attribute reads into a single AX IPC roundtrip when supported,
    /// falling back per-attribute when the batched call fails.
    static func nodeFromElement(_ element: AXUIElement) -> AXNode {
        var valuesRef: CFArray?
        let result = AXUIElementCopyMultipleAttributeValues(
            element, nodeAttributeKeys, AXCopyMultipleAttributeOptions(rawValue: 0), &valuesRef
        )
        if result == .success, let values = valuesRef as? [Any], values.count == 6 {
            let node = AXNode(
                role: stripAXPrefix((values[0] as? String) ?? "unknown"),
                title: values[1] as? String,
                value: stringValue(values[2]),
                description: values[3] as? String,
                enabled: (values[4] as? NSNumber)?.boolValue,
                frame: frameInfoFromAXValue(values[5]),
                children: []
            )
            return textContentFallback(node, element: element)
        }

        let node = AXNode(
            role: stripAXPrefix(string(of: element, key: kAXRoleAttribute) ?? "unknown"),
            title: string(of: element, key: kAXTitleAttribute),
            value: string(of: element, key: kAXValueAttribute),
            description: string(of: element, key: kAXDescriptionAttribute),
            enabled: bool(of: element, key: kAXEnabledAttribute),
            frame: frameInfo(of: element),
            children: []
        )
        return textContentFallback(node, element: element)
    }

    /// Inline character cap for parameterized text pulled into a node's `value`.
    /// Keeps tree/find output bounded; the full string is read via `peek text`.
    static let inlineTextCap = 2000

    /// When a text element exposes no AXValue but does carry parameterized text
    /// (AXStringForRange), fill `value` with a capped preview and flag the overflow.
    private static func textContentFallback(_ node: AXNode, element: AXUIElement) -> AXNode {
        guard node.value?.isEmpty ?? true, textContentRoles.contains(node.role),
              let total = numberOfCharacters(of: element), total > 0,
              let text = string(of: element, offset: 0, length: min(total, inlineTextCap))
        else { return node }
        let truncated = total > inlineTextCap
        return AXNode(
            role: node.role,
            title: node.title,
            value: text,
            description: node.description,
            enabled: node.enabled,
            frame: node.frame,
            children: node.children,
            valueTruncated: truncated ? true : nil,
            valueLength: truncated ? total : nil
        )
    }

    private static func stringValue(_ raw: Any) -> String? {
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        return nil
    }

    private static func frameInfoFromAXValue(_ raw: Any) -> AXNode.FrameInfo? {
        guard CFGetTypeID(raw as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(raw as! AXValue, .cgRect, &rect) else { return nil }
        return AXNode.FrameInfo(
            x: Int(rect.origin.x),
            y: Int(rect.origin.y),
            width: Int(rect.size.width),
            height: Int(rect.size.height)
        )
    }

    /// Check whether an element matches the given filter set without building a
    /// full AXNode. Reads only the attributes each active filter needs, in order
    /// of cheapest-first; returns on first mismatch. `role` is expected to be
    /// already stripped of its "AX" prefix.
    static func elementMatches(
        _ element: AXUIElement,
        role: String?,
        title: String?,
        value: String?,
        description: String?,
        enabled: Bool?
    ) -> Bool {
        if let role {
            let elementRole = stripAXPrefix(string(of: element, key: kAXRoleAttribute) ?? "unknown")
            if elementRole != role { return false }
        }
        if let title {
            let elementTitle = string(of: element, key: kAXTitleAttribute) ?? ""
            let titleHit = elementTitle.localizedCaseInsensitiveContains(title)
            if !titleHit {
                let elementDesc = string(of: element, key: kAXDescriptionAttribute) ?? ""
                if !elementDesc.localizedCaseInsensitiveContains(title) { return false }
            }
        }
        if let value {
            let elementValue = string(of: element, key: kAXValueAttribute) ?? ""
            if !elementValue.localizedCaseInsensitiveContains(value) { return false }
        }
        if let description {
            let elementDesc = string(of: element, key: kAXDescriptionAttribute) ?? ""
            if !elementDesc.localizedCaseInsensitiveContains(description) { return false }
        }
        if let enabled {
            let elementEnabled = bool(of: element, key: kAXEnabledAttribute) ?? true
            if elementEnabled != enabled { return false }
        }
        return true
    }

    // MARK: - Actions

    /// AX errors tolerated *after* the action has been verified as supported by the
    /// element. The supportedActions pre-check is the front-line defense against
    /// bogus or unsupported action names; this set covers the narrow window where
    /// SwiftUI recreates the element between the pre-check and PerformAction,
    /// causing the perform call to surface a benign error even though the action
    /// landed on the recreated node.
    private static let toleratedActionErrors: Set<AXError> = [
        .cannotComplete, .invalidUIElement, .attributeUnsupported
    ]

    /// Return the AX action names supported by an element (with the "AX" prefix stripped).
    /// Returns an empty array if the element exposes no actions or AX failed to enumerate.
    static func supportedActions(of element: AXUIElement) -> [String] {
        var ref: CFArray?
        guard AXUIElementCopyActionNames(element, &ref) == .success,
              let names = ref as? [String] else { return [] }
        return names.map(stripAXPrefix)
    }

    /// Perform an AX action on an element.
    /// Verifies the action is in the element's supported list first to avoid silent no-ops
    /// (e.g. ShowMenu on a regular button, or typoed action names). After dispatch, tolerates
    /// transient AX errors that SwiftUI emits when an element is recreated mid-action.
    static func performAction(_ action: String, on element: AXUIElement) throws {
        let axAction = ensureAXPrefix(action)
        let supported = supportedActions(of: element)
        let stripped = stripAXPrefix(axAction)
        if !supported.contains(stripped) {
            throw PeekError.unsupportedAction(stripped, supported: supported)
        }

        let result = AXUIElementPerformAction(element, axAction as CFString)
        if result != .success, !toleratedActionErrors.contains(result) {
            throw PeekError.actionFailed(axAction, result)
        }
    }

    /// Raise a window (fire-and-forget).
    static func raise(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    // MARK: - Parameterized Text Attributes

    /// Roles whose text content may live behind parameterized attributes
    /// (AXStringForRange) rather than a plain AXValue — e.g. SwiftUI static text.
    static let textContentRoles: Set<String> = ["StaticText", "TextArea", "TextField"]

    /// Total character count of a text element (plain AXNumberOfCharacters).
    static func numberOfCharacters(of element: AXUIElement) -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &ref) == .success,
              let count = ref as? Int else { return nil }
        return count
    }

    /// Read `length` characters starting at `offset` via the parameterized
    /// AXStringForRange attribute. Returns nil if the element doesn't support it.
    static func string(of element: AXUIElement, offset: Int, length: Int) -> String? {
        var range = CFRange(location: offset, length: length)
        guard let param = AXValueCreate(.cfRange, &range) else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, param, &ref
        ) == .success, let str = ref as? String else { return nil }
        return str
    }

    // MARK: - Menu Attributes

    /// Read the keyboard shortcut from a menu item element.
    static func menuShortcut(of element: AXUIElement) -> String? {
        var cmdCharRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuItemCmdCharAttribute as CFString, &cmdCharRef) == .success,
              let cmdChar = cmdCharRef as? String, !cmdChar.isEmpty
        else {
            return nil
        }

        var modRef: CFTypeRef?
        var mods = 0
        if AXUIElementCopyAttributeValue(element, kAXMenuItemCmdModifiersAttribute as CFString, &modRef) == .success,
           let modNum = modRef as? NSNumber {
            mods = modNum.intValue
        }

        var result = ""
        if mods & (1 << 2) != 0 { result += "⌃" }
        if mods & (1 << 1) != 0 { result += "⌥" }
        if mods & (1 << 0) != 0 { result += "⇧" }
        if mods & (1 << 3) == 0 { result += "⌘" } // No command modifier flag
        result += cmdChar

        return result
    }
}

// MARK: - AXError

extension AXError {
    var label: String {
        switch self {
        case .success: "success"
        case .failure: "general failure"
        case .illegalArgument: "illegal argument"
        case .invalidUIElement: "invalid UI element"
        case .invalidUIElementObserver: "invalid observer"
        case .cannotComplete: "cannot complete"
        case .attributeUnsupported: "attribute unsupported"
        case .actionUnsupported: "action not supported on this element"
        case .notificationUnsupported: "notification unsupported"
        case .notImplemented: "not implemented"
        case .notificationAlreadyRegistered: "notification already registered"
        case .notificationNotRegistered: "notification not registered"
        case .apiDisabled: "accessibility API disabled"
        case .noValue: "no value"
        case .parameterizedAttributeUnsupported: "parameterized attribute unsupported"
        case .notEnoughPrecision: "not enough precision"
        @unknown default: "unknown error (\(rawValue))"
        }
    }
}

/// Private API to extract a CGWindowID from an AXUIElement.
/// Apple provides no public bridge between the Accessibility and CGWindow worlds,
/// so this is the standard workaround used by tools like Hammerspoon and yabai.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(
    _ element: AXUIElement,
    _ windowID: UnsafeMutablePointer<CGWindowID>
) -> AXError

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

    /// Read all standard attributes from an element and produce an AXNode (no children).
    static func nodeFromElement(_ element: AXUIElement) -> AXNode {
        AXNode(
            role: stripAXPrefix(string(of: element, key: kAXRoleAttribute) ?? "unknown"),
            title: string(of: element, key: kAXTitleAttribute),
            value: string(of: element, key: kAXValueAttribute),
            description: string(of: element, key: kAXDescriptionAttribute),
            enabled: bool(of: element, key: kAXEnabledAttribute),
            frame: frameInfo(of: element),
            children: []
        )
    }

    // MARK: - Actions

    /// AX errors tolerated when performing actions — SwiftUI apps often return these
    /// even when the action succeeds because the element gets recreated during state changes.
    private static let toleratedActionErrors: Set<AXError> = [
        .cannotComplete, .attributeUnsupported, .invalidUIElement
    ]

    /// Perform an AX action on an element. Tolerates known SwiftUI transient errors.
    static func performAction(_ action: String, on element: AXUIElement) throws {
        let axAction = ensureAXPrefix(action)
        let result = AXUIElementPerformAction(element, axAction as CFString)
        if result != .success, !toleratedActionErrors.contains(result) {
            throw PeekError.actionFailed(axAction, result)
        }
    }

    /// Raise a window (fire-and-forget).
    static func raise(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    // MARK: - Observation

    /// Create an AXObserver for a PID with the given callback and notifications.
    static func createObserver(
        pid: pid_t,
        callback: AXObserverCallback,
        element: AXUIElement,
        notifications: [String],
        context: UnsafeMutableRawPointer
    ) throws -> AXObserver {
        var observer: AXObserver?
        let result = AXObserverCreate(pid, callback, &observer)
        guard result == .success, let observer else {
            throw PeekError.actionFailed("AXObserverCreate", result)
        }

        for notification in notifications {
            AXObserverAddNotification(observer, element, notification as CFString, context)
        }

        return observer
    }

    /// Attach an observer to the current run loop.
    static func attachToRunLoop(_ observer: AXObserver) {
        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
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

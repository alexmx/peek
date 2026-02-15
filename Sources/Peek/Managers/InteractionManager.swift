import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum InteractionManager {
    private static let maxDepth = 50
    /// Activate an app and raise its window.
    static func activate(pid: pid_t, windowID: CGWindowID) throws -> ActivateResult {
        try PermissionManager.requireAccessibility()

        guard let app = NSRunningApplication(processIdentifier: pid) else {
            throw PeekError.windowNotFound(windowID)
        }

        app.activate()

        // findWindow() handles cross-Space polling automatically
        let window = try AccessibilityTreeManager.findWindow(pid: pid, windowID: windowID)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)

        return ActivateResult(
            pid: pid,
            windowID: windowID,
            app: app.localizedName ?? "Unknown"
        )
    }

    struct ActivateResult: Encodable {
        let pid: Int32
        let windowID: UInt32
        let app: String
    }

    /// Click at screen coordinates.
    static func click(x: Double, y: Double) {
        let point = CGPoint(x: x, y: y)

        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)

        mouseDown?.post(tap: .cghidEventTap)
        usleep(50000) // 50ms between down and up
        mouseUp?.post(tap: .cghidEventTap)
    }

    /// Type a string by posting key events for each character.
    static func type(text: String) {
        for char in text {
            let str = String(char) as CFString
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)

            keyDown?.keyboardSetUnicodeString(stringLength: 1, unicodeString: Array(str as String).map { $0.utf16.first! })
            keyUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: Array(str as String).map { $0.utf16.first! })

            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            usleep(10000) // 10ms between keystrokes
        }
    }

    /// Perform an AX action on the first element matching the given filters.
    static func performAction(
        pid: pid_t,
        windowID: CGWindowID,
        action: String,
        role: String?,
        title: String?,
        value: String?,
        description: String?
    ) throws -> AXNode {
        try PermissionManager.requireAccessibility()

        let window = try AccessibilityTreeManager.findWindow(pid: pid, windowID: windowID)
        guard let element = findFirstElement(
            in: window,
            role: role.map(stripAXPrefix),
            title: title,
            value: value,
            description: description,
            depth: 0
        ) else {
            throw PeekError.elementNotFound
        }

        let axAction = ensureAXPrefix(action)
        let result = AXUIElementPerformAction(element.ref, axAction as CFString)
        // SwiftUI apps often return errors even when the action succeeds,
        // because the element gets recreated during the state change.
        // Only fail on truly fatal errors.
        let toleratedErrors: Set<AXError> = [.cannotComplete, .attributeUnsupported, .invalidUIElement]
        if result != .success, !toleratedErrors.contains(result) {
            throw PeekError.actionFailed(axAction, result)
        }

        return element.node
    }

    /// Perform an AX action on all elements matching the given filters.
    static func performActionOnAll(
        pid: pid_t,
        windowID: CGWindowID,
        action: String,
        role: String?,
        title: String?,
        value: String?,
        description: String?
    ) throws -> [AXNode] {
        try PermissionManager.requireAccessibility()

        let window = try AccessibilityTreeManager.findWindow(pid: pid, windowID: windowID)
        var elements: [ElementMatch] = []
        findAllElements(
            in: window,
            role: role.map(stripAXPrefix),
            title: title,
            value: value,
            description: description,
            depth: 0,
            results: &elements
        )

        guard !elements.isEmpty else {
            throw PeekError.elementNotFound
        }

        let axAction = ensureAXPrefix(action)
        let toleratedErrors: Set<AXError> = [.cannotComplete, .attributeUnsupported, .invalidUIElement]
        for element in elements {
            let result = AXUIElementPerformAction(element.ref, axAction as CFString)
            if result != .success, !toleratedErrors.contains(result) {
                throw PeekError.actionFailed(axAction, result)
            }
        }

        return elements.map(\.node)
    }

    private struct ElementMatch {
        let ref: AXUIElement
        let node: AXNode
    }

    private static func nodeFromElement(_ element: AXUIElement) -> AXNode {
        AXNode(
            role: stripAXPrefix(axString(of: element, key: kAXRoleAttribute) ?? "unknown"),
            title: axString(of: element, key: kAXTitleAttribute),
            value: axString(of: element, key: kAXValueAttribute),
            description: axString(of: element, key: kAXDescriptionAttribute),
            frame: axFrameInfo(of: element),
            children: []
        )
    }

    private static func findFirstElement(
        in element: AXUIElement,
        role: String?,
        title: String?,
        value: String?,
        description: String?,
        depth: Int
    ) -> ElementMatch? {
        guard depth < maxDepth else { return nil }

        let node = nodeFromElement(element)
        if node.matches(role: role, title: title, value: value, description: description) {
            return ElementMatch(ref: element, node: node)
        }

        if let children = axChildren(of: element) {
            for child in children {
                if let found = findFirstElement(
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

    private static func findAllElements(
        in element: AXUIElement,
        role: String?,
        title: String?,
        value: String?,
        description: String?,
        depth: Int,
        results: inout [ElementMatch]
    ) {
        guard depth < maxDepth else { return }

        let node = nodeFromElement(element)
        if node.matches(role: role, title: title, value: value, description: description) {
            results.append(ElementMatch(ref: element, node: node))
        }

        if let children = axChildren(of: element) {
            for child in children {
                findAllElements(
                    in: child,
                    role: role,
                    title: title,
                    value: value,
                    description: description,
                    depth: depth + 1,
                    results: &results
                )
            }
        }
    }
}

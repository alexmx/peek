import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum InteractionManager {
    /// Activate an app and raise its window.
    static func activate(pid: pid_t, windowID: CGWindowID) throws -> ActivateResult {
        try PermissionManager.requireAccessibility()

        guard let app = NSRunningApplication(processIdentifier: pid) else {
            throw PeekError.windowNotFound(windowID)
        }

        app.activate()

        let window = try AXElement.resolveWindow(pid: pid, windowID: windowID)
        AXElement.raise(window)

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

        let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )

        mouseDown?.post(tap: .cghidEventTap)
        usleep(50000) // 50ms between down and up
        mouseUp?.post(tap: .cghidEventTap)
    }

    /// Type a string by posting key events for each character.
    static func type(text: String) {
        for char in text {
            let (keyCode, shift) = KeyMapping.lookup(char)
            let utf16 = Array(String(char).utf16)

            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)

            keyDown?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

            if shift {
                keyDown?.flags = .maskShift
                keyUp?.flags = .maskShift
            }

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

        let window = try AXElement.resolveWindow(pid: pid, windowID: windowID)
        guard let match = AXElement.findFirst(
            in: window,
            role: role,
            title: title,
            value: value,
            description: description
        ) else {
            throw PeekError.elementNotFound
        }

        try AXElement.performAction(action, on: match.ref)
        return match.node
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

        let window = try AXElement.resolveWindow(pid: pid, windowID: windowID)
        let matches = AXElement.findAll(
            in: window,
            role: role,
            title: title,
            value: value,
            description: description
        )

        guard !matches.isEmpty else {
            throw PeekError.elementNotFound
        }

        for match in matches {
            try AXElement.performAction(action, on: match.ref)
        }

        return matches.map(\.node)
    }
}

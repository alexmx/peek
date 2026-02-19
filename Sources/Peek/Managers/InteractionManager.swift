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

        let window = try AccessibilityManager.resolveWindow(pid: pid, windowID: windowID)
        AXBridge.raise(window)

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

    /// Drag from one point to another (simulates a touch swipe in apps like iOS Simulator).
    static func drag(fromX: Double, fromY: Double, toX: Double, toY: Double) {
        let start = CGPoint(x: fromX, y: fromY)
        let end = CGPoint(x: toX, y: toY)

        let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: start,
            mouseButton: .left
        )
        mouseDown?.post(tap: .cghidEventTap)
        usleep(50000)

        // Interpolate in small steps for a smooth drag
        let steps = 20
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let x = fromX + (toX - fromX) * t
            let y = fromY + (toY - fromY) * t
            let point = CGPoint(x: x, y: y)
            let drag = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: point,
                mouseButton: .left
            )
            drag?.post(tap: .cghidEventTap)
            usleep(10000) // 10ms between steps
        }

        let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: end,
            mouseButton: .left
        )
        mouseUp?.post(tap: .cghidEventTap)
    }

    /// Scroll at screen coordinates.
    /// deltaY: positive = scroll down (content moves up), negative = scroll up.
    /// deltaX: positive = scroll right (content moves left), negative = scroll left.
    static func scroll(x: Double, y: Double, deltaX: Int32, deltaY: Int32) {
        let point = CGPoint(x: x, y: y)

        // Move cursor to target so scroll event reaches the correct view
        let move = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        move?.post(tap: .cghidEventTap)
        usleep(50000)

        // CGEvent: positive wheel1 = scroll up, so negate for our convention (positive = down)
        // Mark as continuous (trackpad-style) for broader app compatibility
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: -deltaY,
            wheel2: -deltaX,
            wheel3: 0
        )
        event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event?.post(tap: .cghidEventTap)
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

        let window = try AccessibilityManager.resolveWindow(pid: pid, windowID: windowID)
        guard let match = AccessibilityManager.findFirst(
            in: window,
            role: role,
            title: title,
            value: value,
            description: description
        ) else {
            throw PeekError.elementNotFound
        }

        try AXBridge.performAction(action, on: match.ref)
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

        let window = try AccessibilityManager.resolveWindow(pid: pid, windowID: windowID)
        let matches = AccessibilityManager.findAll(
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
            try AXBridge.performAction(action, on: match.ref)
        }

        return matches.map(\.node)
    }
}

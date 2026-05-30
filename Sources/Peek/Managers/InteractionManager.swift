import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum InteractionManager {
    /// Activate an app and raise its window.
    /// Polls frontmost + z-order after activation; retries once if macOS dropped the request.
    /// Throws `PeekError.activationFailed` if the app is still not frontmost after the budget.
    static func activate(pid: pid_t, windowID: CGWindowID) async throws -> ActivateResult {
        try PermissionManager.requireAccessibility()

        guard let app = NSRunningApplication(processIdentifier: pid) else {
            throw PeekError.windowNotFound(windowID)
        }

        let window = try AccessibilityManager.resolveWindow(pid: pid, windowID: windowID)

        let name = app.localizedName ?? "Unknown"
        if try await !activateAndAwait(app: app, window: window, windowID: windowID, timeout: 0.5) {
            // One bounded retry — cooperative activation occasionally drops the first call.
            if try await !activateAndAwait(app: app, window: window, windowID: windowID, timeout: 0.3) {
                throw PeekError.activationFailed(pid, name)
            }
        }

        return ActivateResult(pid: pid, windowID: windowID, app: name)
    }

    /// Activate an app without raising a specific window. Useful for apps that have no
    /// windows (e.g. Finder when no Finder windows are open) — the menu bar still
    /// belongs to a running app and we need to bring it to the front to interact.
    static func activateApp(pid: pid_t) async throws -> ActivateResult {
        try PermissionManager.requireAccessibility()

        guard let app = NSRunningApplication(processIdentifier: pid) else {
            throw PeekError.appNotFound("pid \(pid)")
        }
        let name = app.localizedName ?? "Unknown"

        if try await !activateAppAndAwait(app: app, timeout: 0.5) {
            if try await !activateAppAndAwait(app: app, timeout: 0.3) {
                throw PeekError.activationFailed(pid, name)
            }
        }

        return ActivateResult(pid: pid, windowID: 0, app: name)
    }

    private static let tickNanoseconds: UInt64 = 25_000_000   // 25ms
    private static let settleNanoseconds: UInt64 = 50_000_000 // 50ms

    private static func activateAppAndAwait(app: NSRunningApplication, timeout: TimeInterval) async throws -> Bool {
        app.activate()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isFrontmost(app) {
                try await Task.sleep(nanoseconds: settleNanoseconds)
                return true
            }
            try await Task.sleep(nanoseconds: tickNanoseconds)
        }
        return isFrontmost(app)
    }

    /// Request activation and poll until the app is frontmost AND the target window
    /// is the topmost normal-layer window, or `timeout` elapses.
    private static func activateAndAwait(
        app: NSRunningApplication,
        window: AXUIElement,
        windowID: CGWindowID,
        timeout: TimeInterval
    ) async throws -> Bool {
        app.activate()
        AXBridge.raise(window)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isFrontmost(app), isWindowTopmost(windowID) {
                try await Task.sleep(nanoseconds: settleNanoseconds)
                return true
            }
            try await Task.sleep(nanoseconds: tickNanoseconds)
        }
        return isFrontmost(app) && isWindowTopmost(windowID)
    }

    /// True if `app` is the workspace-frontmost application.
    /// `NSWorkspace.frontmostApplication` reflects window-server-acknowledged state
    /// more reliably than `NSRunningApplication.isActive`, which can flip true while
    /// the actual z-order reorder is still in flight.
    private static func isFrontmost(_ app: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    /// True if `windowID` is the front-most normal-layer (user) window on screen.
    /// Floating layers (menu bar, dock, status items) are skipped so they don't mask
    /// our window's true z-position.
    private static func isWindowTopmost(_ windowID: CGWindowID) -> Bool {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return true
        }
        for info in windows {
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            if layer != 0 { continue }
            return (info[kCGWindowNumber as String] as? CGWindowID) == windowID
        }
        return true
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

    /// AX actions that only take visible effect when the target app is frontmost.
    /// `Press` works on backgrounded buttons because AX dispatches directly, but
    /// `ShowMenu` needs the app's event loop to render the popover.
    private static let focusRequiringActions: Set<String> = ["ShowMenu"]

    /// Returns true if the given AX action requires the target app to be FG to work.
    /// Accepts both `Press` and `AXPress` style names.
    private static func actionNeedsFocus(_ action: String) -> Bool {
        let stripped = action.hasPrefix("AX") ? String(action.dropFirst(2)) : action
        return focusRequiringActions.contains(stripped)
    }

    /// Perform an AX action on the first element matching the given filters.
    /// Auto-activates the target app only if the action is in `focusRequiringActions`.
    static func performAction(
        pid: pid_t,
        windowID: CGWindowID,
        action: String,
        role: String?,
        title: String?,
        value: String?,
        description: String?
    ) async throws -> AXNode {
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

        if actionNeedsFocus(action) {
            _ = try await activate(pid: pid, windowID: windowID)
        }

        try AXBridge.performAction(action, on: match.ref)
        return match.node
    }

    /// Perform an AX action on all elements matching the given filters.
    /// Auto-activates the target app only if the action is in `focusRequiringActions`.
    static func performActionOnAll(
        pid: pid_t,
        windowID: CGWindowID,
        action: String,
        role: String?,
        title: String?,
        value: String?,
        description: String?
    ) async throws -> [AXNode] {
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

        if actionNeedsFocus(action) {
            _ = try await activate(pid: pid, windowID: windowID)
        }

        for match in matches {
            try AXBridge.performAction(action, on: match.ref)
        }

        return matches.map(\.node)
    }
}

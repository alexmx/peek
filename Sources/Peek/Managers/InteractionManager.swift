import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum InteractionManager {
    /// Shared source for synthesized mouse/scroll events. The local-events suppression
    /// interval makes the window server suppress the user's *physical* mouse for a short
    /// window after each posted event — so a hand moving the mouse mid-click can't
    /// interleave a real `.mouseMoved` between our down and up (which would corrupt the
    /// click into a drag) or yank the cursor off-target. 0.15s comfortably covers the
    /// ~30ms down→up gap and lingers only briefly after the gesture.
    nonisolated(unsafe) static let eventSource: CGEventSource? = {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0.15
        return source
    }()

    /// Activate an app and raise its window.
    /// Polls frontmost + z-order after activation; retries once if macOS dropped the request.
    /// Throws `PeekError.activationFailed` if the app is still not frontmost after the budget.
    static func activate(pid: pid_t, windowID: CGWindowID) async throws -> ActivateResult {
        // Windowless apps (Dock, Control Center, status-menu helpers) — there's no
        // AXWindow to raise. Activate the app only; skip the window-topmost check.
        if windowID == 0 {
            return try await activateApp(pid: pid)
        }

        // Activation can change which windows are on-screen / on the current Space, so the
        // cached window list (apps/find/resolve) is stale afterward — refresh on exit.
        defer { WindowManager.invalidateCache() }

        try PermissionManager.requireAccessibility()

        guard let app = NSRunningApplication(processIdentifier: pid) else {
            throw PeekError.windowNotFound(windowID)
        }

        let name = app.localizedName ?? "Unknown"

        if isFrontmost(app), isWindowTopmost(windowID) {
            return ActivateResult(pid: pid, windowID: windowID, app: name)
        }

        let window = try AccessibilityManager.resolveWindow(pid: pid, windowID: windowID)

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
        // See activate(_:): a fronted app may surface windows that were off-screen /
        // on another Space, so the window-list cache is stale after activation.
        defer { WindowManager.invalidateCache() }

        try PermissionManager.requireAccessibility()

        guard let app = NSRunningApplication(processIdentifier: pid) else {
            throw PeekError.appNotFound("pid \(pid)")
        }
        let name = app.localizedName ?? "Unknown"

        if isFrontmost(app) {
            return ActivateResult(pid: pid, windowID: 0, app: name)
        }

        if try await !activateAppAndAwait(app: app, timeout: 0.5) {
            if try await !activateAppAndAwait(app: app, timeout: 0.3) {
                throw PeekError.activationFailed(pid, name)
            }
        }

        return ActivateResult(pid: pid, windowID: 0, app: name)
    }

    private static let tickNanoseconds: UInt64 = 25_000_000 // 25ms
    private static let settleNanoseconds: UInt64 = 20_000_000 // 20ms

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

    enum MouseButton: String {
        case left, right
    }

    /// Click at screen coordinates. `count` posts that many consecutive click pairs
    /// with the `clickState` field set (1, 2, or 3) so AppKit treats them as a single
    /// click, double-click, or triple-click — used for word/line selection in text views.
    /// `button` picks the mouse button (left or right).
    static func click(x: Double, y: Double, count: Int = 1, button: MouseButton = .left) {
        let point = CGPoint(x: x, y: y)
        let clamped = max(1, min(count, 3))
        let (downType, upType, btn): (CGEventType, CGEventType, CGMouseButton) = switch button {
        case .left: (.leftMouseDown, .leftMouseUp, .left)
        case .right: (.rightMouseDown, .rightMouseUp, .right)
        }

        // Prime the target's hover/tracking state before pressing. A synthetic mouseDown
        // with no preceding .mouseMoved can silently no-op on controls that gate on
        // mouseEntered/cursorUpdate (NSOutlineView/NSTableView rows especially) — the
        // reason a manual peek_move then peek_click works where a bare click doesn't.
        CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(15000)

        for i in 1...clamped {
            let down = CGEvent(
                mouseEventSource: eventSource,
                mouseType: downType,
                mouseCursorPosition: point,
                mouseButton: btn
            )
            let up = CGEvent(
                mouseEventSource: eventSource,
                mouseType: upType,
                mouseCursorPosition: point,
                mouseButton: btn
            )
            down?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            up?.setIntegerValueField(.mouseEventClickState, value: Int64(i))

            down?.post(tap: .cghidEventTap)
            usleep(30000)
            up?.post(tap: .cghidEventTap)
            if i < clamped {
                usleep(50000) // inter-click gap, well under macOS's ~500ms double-click threshold
            }
        }
    }

    static func drag(fromX: Double, fromY: Double, toX: Double, toY: Double) {
        let dx = toX - fromX
        let dy = toY - fromY
        let distance = (dx * dx + dy * dy).squareRoot()

        let mouseDown = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .leftMouseDown,
            mouseCursorPosition: CGPoint(x: fromX, y: fromY),
            mouseButton: .left
        )
        mouseDown?.post(tap: .cghidEventTap)
        usleep(100_000)

        let steps = max(10, min(40, Int(distance / 5)))
        let dragInitThreshold = 6.0
        for i in 1...steps {
            var t = Double(i) / Double(steps)
            if i == 1, distance > 0 {
                t = max(t, min(1.0, dragInitThreshold / distance))
            }
            let point = CGPoint(x: fromX + dx * t, y: fromY + dy * t)
            let drag = CGEvent(
                mouseEventSource: eventSource,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: point,
                mouseButton: .left
            )
            drag?.post(tap: .cghidEventTap)
            usleep(10000)
        }

        let mouseUp = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .leftMouseUp,
            mouseCursorPosition: CGPoint(x: toX, y: toY),
            mouseButton: .left
        )
        mouseUp?.post(tap: .cghidEventTap)
    }

    /// Move the cursor to a screen point by posting `.mouseMoved` events — no buttons pressed.
    /// Used to drive hover-state UI (NSTrackingArea: mouseEntered/mouseMoved/mouseExited, cursorUpdate).
    ///
    /// - Parameters:
    ///   - fromX/fromY: optional start point. When provided alongside `steps > 1`, intermediate
    ///     `.mouseMoved` events are interpolated from (fromX, fromY) to (toX, toY) — useful for
    ///     apps whose tracking logic requires continuous motion rather than a single jump.
    ///   - toX/toY: destination screen coordinates.
    ///   - steps: number of intermediate moves to post (clamped to >= 1). 1 = single jump.
    ///   - dwellMs: milliseconds to sleep after the final move so the caller can capture the
    ///     hover state before something else perturbs the cursor.
    ///
    /// Posts via `.cghidEventTap` with `mouseEventSource: eventSource` — the same path `scroll` already
    /// uses to seed cursor position, which routes through NSTrackingArea correctly.
    static func move(
        fromX: Double? = nil,
        fromY: Double? = nil,
        toX: Double,
        toY: Double,
        steps: Int = 1,
        dwellMs: UInt32 = 0
    ) {
        let clampedSteps = max(1, steps)
        let startX = fromX ?? toX
        let startY = fromY ?? toY

        if clampedSteps == 1 || (fromX == nil && fromY == nil) {
            let move = CGEvent(
                mouseEventSource: eventSource,
                mouseType: .mouseMoved,
                mouseCursorPosition: CGPoint(x: toX, y: toY),
                mouseButton: .left
            )
            move?.post(tap: .cghidEventTap)
        } else {
            let dx = toX - startX
            let dy = toY - startY
            for i in 1...clampedSteps {
                let t = Double(i) / Double(clampedSteps)
                let point = CGPoint(x: startX + dx * t, y: startY + dy * t)
                let move = CGEvent(
                    mouseEventSource: eventSource,
                    mouseType: .mouseMoved,
                    mouseCursorPosition: point,
                    mouseButton: .left
                )
                move?.post(tap: .cghidEventTap)
                if i < clampedSteps {
                    usleep(10000) // 10ms between intermediate moves, matches drag()'s cadence
                }
            }
        }

        // Flush: synthetic .mouseMoved events are dispatched asynchronously by the window
        // server, so an immediate readback of CGEvent.location or AXUIElementCopyElementAtPosition
        // races the dispatch and reports stale state. A small floor sleep guarantees the
        // event has been applied before move() returns. Honor an explicit dwell that's
        // larger; otherwise just pay the 15ms flush.
        let totalSleepMs = max(dwellMs, 15)
        usleep(totalSleepMs * 1000)
    }

    /// Scroll at screen coordinates.
    /// deltaY: positive = scroll down (content moves up), negative = scroll up.
    /// deltaX: positive = scroll right (content moves left), negative = scroll left.
    static func scroll(x: Double, y: Double, deltaX: Int32, deltaY: Int32) {
        let point = CGPoint(x: x, y: y)

        // Move cursor to target so scroll event reaches the correct view
        let move = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        move?.post(tap: .cghidEventTap)
        usleep(50000)

        // CGEvent: positive wheel1 = scroll up, so negate for our convention (positive = down)
        // Mark as continuous (trackpad-style) for broader app compatibility
        let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: -deltaY,
            wheel2: -deltaX,
            wheel3: 0
        )
        event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event?.post(tap: .cghidEventTap)
    }

    static func type(text: String, delayMs: UInt32 = 5) {
        let usec = delayMs * 1000
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
            usleep(usec)
        }
    }

    static func sendKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
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

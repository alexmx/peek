import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum InteractionManager {
    /// Shared event source for synthesized mouse/scroll events. The 0.15s suppression
    /// interval stops the user's physical mouse from interleaving between our down/up
    /// (which would corrupt a click into a drag) or yanking the cursor off-target.
    /// `nonisolated(unsafe)`: CGEventSource isn't Sendable but this is immutable after init.
    nonisolated(unsafe) static let eventSource: CGEventSource? = {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0.15
        return source
    }()

    /// Inter-event gesture pause, in milliseconds. Yields the cooperative thread (unlike
    /// usleep) so long gestures don't starve concurrent work; swallows cancellation so an
    /// in-flight gesture still completes and never leaves a button down / scroll phase open.
    private static func pause(_ milliseconds: Double) async {
        try? await Delay.milliseconds(milliseconds)
    }

    /// Create and post a synthesized mouse event through the shared event source.
    private static func postMouseEvent(_ type: CGEventType, at point: CGPoint, button: CGMouseButton = .left) {
        CGEvent(
            mouseEventSource: eventSource,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        )?.post(tap: .cghidEventTap)
    }

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

    private static let tickMs: Double = 25
    private static let settleMs: Double = 20

    private static func activateAppAndAwait(app: NSRunningApplication, timeout: TimeInterval) async throws -> Bool {
        app.activate()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isFrontmost(app) {
                try await Delay.milliseconds(settleMs)
                return true
            }
            try await Delay.milliseconds(tickMs)
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
                try await Delay.milliseconds(settleMs)
                return true
            }
            try await Delay.milliseconds(tickMs)
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

    // MARK: - Coordinate targeting

    private struct HitWindow {
        let pid: pid_t
        let windowID: CGWindowID
        let bounds: CGRect
    }

    /// On-screen, normal-layer (user) windows ordered front-to-back, with screen bounds.
    private static func onScreenWindowsFrontToBack() -> [HitWindow] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return infos.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int ?? -1) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let num = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary)
            else { return nil }
            return HitWindow(pid: pid, windowID: num, bounds: rect)
        }
    }

    private static func appName(of pid: pid_t) -> String {
        NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
    }

    /// Verify each screen point lands on the intended app/window before a coordinate
    /// event fires. After activation the app is frontmost, but a point may still be over
    /// another window — stale coordinates, an always-on-top panel, or an occluded sibling.
    /// Self-heals by raising the target window under the point; throws when a point isn't
    /// over the target at all. `windowID == nil` checks app ownership only; non-nil
    /// requires that exact window on top. Callers pass it only when a target was given.
    static func ensureOnTarget(points: [(x: Int, y: Int)], pid: pid_t, windowID: CGWindowID?) async throws {
        for p in points {
            try await ensurePointOnTarget(x: p.x, y: p.y, pid: pid, windowID: windowID)
        }
    }

    private static func ensurePointOnTarget(x: Int, y: Int, pid: pid_t, windowID: CGWindowID?) async throws {
        let point = CGPoint(x: Double(x), y: Double(y))
        func onTarget() -> Bool {
            guard let top = onScreenWindowsFrontToBack().first(where: { $0.bounds.contains(point) })
            else { return false }
            return top.pid == pid && (windowID == nil || top.windowID == windowID)
        }
        if onTarget() { return }
        // Self-heal: a target window is under the point but occluded — raise it.
        if let tw = onScreenWindowsFrontToBack().first(where: {
            $0.bounds.contains(point) && $0.pid == pid && (windowID == nil || $0.windowID == windowID)
        }), let element = AXBridge.window(pid: pid, windowID: tw.windowID) {
            AXBridge.raise(element)
            try await Delay.milliseconds(120) // let the window-server reorder
            if onTarget() { return }
        }
        let actual = onScreenWindowsFrontToBack().first(where: { $0.bounds.contains(point) })
            .map { appName(of: $0.pid) } ?? "no window"
        throw PeekError.coordinateOffTarget(x: x, y: y, target: appName(of: pid), actual: actual)
    }

    enum MouseButton: String {
        case left, right
    }

    /// Click at screen coordinates. `count` posts that many consecutive click pairs
    /// with the `clickState` field set (1, 2, or 3) so AppKit treats them as a single
    /// click, double-click, or triple-click — used for word/line selection in text views.
    /// `button` picks the mouse button (left or right).
    static func click(x: Double, y: Double, count: Int = 1, button: MouseButton = .left) async {
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
        postMouseEvent(.mouseMoved, at: point)
        await pause(15)

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
            await pause(30)
            up?.post(tap: .cghidEventTap)
            if i < clamped {
                await pause(50) // inter-click gap, well under macOS's ~500ms double-click threshold
            }
        }
    }

    static func drag(fromX: Double, fromY: Double, toX: Double, toY: Double) async {
        let dx = toX - fromX
        let dy = toY - fromY
        let distance = (dx * dx + dy * dy).squareRoot()

        postMouseEvent(.leftMouseDown, at: CGPoint(x: fromX, y: fromY))
        await pause(100)

        let steps = max(10, min(40, Int(distance / 5)))
        let dragInitThreshold = 6.0
        for i in 1...steps {
            var t = Double(i) / Double(steps)
            if i == 1, distance > 0 {
                t = max(t, min(1.0, dragInitThreshold / distance))
            }
            let point = CGPoint(x: fromX + dx * t, y: fromY + dy * t)
            postMouseEvent(.leftMouseDragged, at: point)
            await pause(10)
        }

        postMouseEvent(.leftMouseUp, at: CGPoint(x: toX, y: toY))
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
    ) async {
        let clampedSteps = max(1, steps)
        let startX = fromX ?? toX
        let startY = fromY ?? toY

        if clampedSteps == 1 || (fromX == nil && fromY == nil) {
            postMouseEvent(.mouseMoved, at: CGPoint(x: toX, y: toY))
        } else {
            let dx = toX - startX
            let dy = toY - startY
            for i in 1...clampedSteps {
                let t = Double(i) / Double(clampedSteps)
                let point = CGPoint(x: startX + dx * t, y: startY + dy * t)
                postMouseEvent(.mouseMoved, at: point)
                if i < clampedSteps {
                    await pause(10) // between moves, matches drag()'s cadence
                }
            }
        }

        // Flush: synthetic .mouseMoved events dispatch asynchronously, so an immediate
        // AX/cursor readback races them. A floor sleep ensures the move applied first.
        let totalSleepMs = max(dwellMs, 15)
        await pause(Double(totalSleepMs))
    }

    /// Scroll at screen coordinates. Positive deltaY/deltaX scroll down/right.
    /// steps == 1 posts one instant event; steps > 1 (or durationMs) spreads the delta
    /// across a phased ease-in-out stream for smooth motion, preserving the total delta.
    static func scroll(
        x: Double,
        y: Double,
        deltaX: Int32,
        deltaY: Int32,
        steps: Int = 1,
        durationMs: UInt32 = 0
    ) async {
        let point = CGPoint(x: x, y: y)

        // Move cursor to target so scroll event reaches the correct view
        postMouseEvent(.mouseMoved, at: point)
        await pause(50)

        let smooth = steps > 1 || durationMs > 0
        if !smooth {
            // Single-shot: positive wheel1 = scroll up, so negate for our convention
            // (positive = down). Marked continuous (trackpad-style) for broad compatibility.
            postScrollEvent(deltaX: deltaX, deltaY: deltaY, phase: nil)
            return
        }

        // Resolve the step/duration pair, filling in whichever the caller omitted.
        let resolvedSteps = steps > 1 ? steps : max(2, Int(durationMs) / 16)
        let resolvedDuration = durationMs > 0 ? durationMs : UInt32(resolvedSteps * 16)
        let sleepPerStepMs = Double(resolvedDuration) / Double(resolvedSteps)

        // Ease-in-out weights (∝ t·(1−t)): small at the ends, large in the middle.
        let weights = (1...resolvedSteps).map { i -> Double in
            let t = (Double(i) - 0.5) / Double(resolvedSteps)
            return t * (1 - t)
        }
        let dys = distributeDelta(deltaY, across: weights)
        let dxs = distributeDelta(deltaX, across: weights)

        for i in 0..<resolvedSteps {
            let phase: Int64 = i == 0 ? 1 : 2 // kCGScrollPhaseBegan : kCGScrollPhaseChanged
            postScrollEvent(deltaX: dxs[i], deltaY: dys[i], phase: phase)
            await pause(sleepPerStepMs)
        }
        // Terminate the gesture so the view settles (kCGScrollPhaseEnded, zero delta).
        postScrollEvent(deltaX: 0, deltaY: 0, phase: 4)
    }

    /// Post one continuous (pixel-unit) scroll-wheel event. `phase`, when non-nil, sets
    /// `kCGScrollWheelEventScrollPhase` so apps render the gesture as a smooth stream.
    private static func postScrollEvent(deltaX: Int32, deltaY: Int32, phase: Int64?) {
        let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: -deltaY,
            wheel2: -deltaX,
            wheel3: 0
        )
        event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        if let phase {
            event?.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        }
        event?.post(tap: .cghidEventTap)
    }

    /// Split an integer `total` across `weights` so the per-step values sum back to
    /// exactly `total`. Uses cumulative rounding: each step gets the difference between
    /// the running rounded target and what's been assigned, absorbing the remainder.
    static func distributeDelta(_ total: Int32, across weights: [Double]) -> [Int32] {
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return weights.map { _ in 0 } }
        var out = [Int32]()
        out.reserveCapacity(weights.count)
        var assigned: Int32 = 0
        var acc = 0.0
        for w in weights {
            acc += w / sum * Double(total)
            let target = Int32(acc.rounded())
            out.append(target - assigned)
            assigned = target
        }
        return out
    }

    static func type(text: String, delayMs: UInt32 = 5) async {
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
            await pause(Double(delayMs))
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

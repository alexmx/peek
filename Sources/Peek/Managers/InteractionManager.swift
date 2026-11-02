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

        // Skip activation only when the window is verifiably on top — a window missing from
        // the on-screen list (background tab, minimized, other Space) still needs the full path.
        if isFrontmost(app), isWindowTopmost(windowID, requireOnScreen: true) {
            return ActivateResult(pid: pid, windowID: windowID, app: name)
        }

        let window = try AccessibilityManager.resolveWindow(pid: pid, windowID: windowID)
        try await requestActivation(
            pid: pid, name: name,
            request: {
                app.activate()
                AXBridge.raise(window)
            },
            until: { isFrontmost(app) && isWindowTopmost(windowID) }
        )

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

        try await requestActivation(
            pid: pid, name: name,
            request: { app.activate() },
            until: { isFrontmost(app) }
        )

        return ActivateResult(pid: pid, windowID: 0, app: name)
    }

    private static let tickMs: Double = 25
    private static let settleMs: Double = 20

    /// Run `request`, then poll until `isDone` holds (plus a short settle), retrying once —
    /// cooperative activation occasionally drops the first request. Throws
    /// `activationFailed` if both attempts (0.5s, then 0.3s) time out.
    private static func requestActivation(
        pid: pid_t,
        name: String,
        request: () -> Void,
        until isDone: () -> Bool
    ) async throws {
        for timeout: TimeInterval in [0.5, 0.3] {
            request()
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if isDone() {
                    try await Delay.milliseconds(settleMs)
                    return
                }
                try await Delay.milliseconds(tickMs)
            }
            if isDone() { return }
        }
        throw PeekError.activationFailed(pid, name)
    }

    /// True if `app` is the workspace-frontmost application.
    /// `NSWorkspace.frontmostApplication` reflects window-server-acknowledged state
    /// more reliably than `NSRunningApplication.isActive`, which can flip true while
    /// the actual z-order reorder is still in flight.
    private static func isFrontmost(_ app: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    /// True if `windowID` is the front-most window *within its own CG window layer*.
    ///
    /// Normal app windows live at layer 0, so for them this reads as "is our window the
    /// front-most user window on screen." But panels, non-activating panels, and SwiftUI
    /// MenuBarExtra windows float at higher layers; scoping the comparison to the target's
    /// own layer keeps the check meaningful for them. Comparing a layer-3 panel against the
    /// front-most layer-0 window never matches, so a frontmost, focused panel would look
    /// permanently "not topmost" — stalling activation until it throws `activationFailed`
    /// even though the app is frontmost and the field focused. If the window isn't in the
    /// on-screen list at all (minimized, on another Space, or a kind CGWindowList doesn't
    /// report), we can't verify z-order — don't block, unless `requireOnScreen` is set.
    private static func isWindowTopmost(_ windowID: CGWindowID, requireOnScreen: Bool = false) -> Bool {
        isTopmostInLayer(
            windowID: windowID,
            windows: WindowManager.windowRecords([.optionOnScreenOnly, .excludeDesktopElements]),
            requireOnScreen: requireOnScreen
        )
    }

    /// Pure z-order check: is `windowID` the front-most window within its own CG window
    /// layer, given a front-to-back `windows` list (an on-screen
    /// `WindowManager.windowRecords` query)? Factored out of
    /// `isWindowTopmost` so the layer-scoping logic is deterministically testable without
    /// a live window server.
    static func isTopmostInLayer(windowID: CGWindowID, windows: [WindowRecord], requireOnScreen: Bool = false) -> Bool {
        guard let target = windows.first(where: { $0.windowID == windowID }) else {
            return !requireOnScreen
        }
        let frontmostInLayer = windows.first(where: { $0.layer == target.layer })
        return frontmostInLayer?.windowID == windowID
    }

    struct ActivateResult: Encodable {
        let pid: Int32
        let windowID: UInt32
        let app: String
    }

    // MARK: - Coordinate targeting

    /// On-screen, normal-layer (user) windows ordered front-to-back, with screen bounds.
    private static func onScreenWindowsFrontToBack() -> [WindowRecord] {
        WindowManager.windowRecords([.optionOnScreenOnly, .excludeDesktopElements]).filter { $0.layer == 0 }
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

    /// Longest press hold `click`/`drag` accept, in ms. A long-press needs ~0.6s; the cap
    /// keeps a gesture inside the MCP tool timeout.
    private static let maxHoldMs = 5000

    /// How long `drag` holds the press still before moving, unless the caller says otherwise.
    static let defaultDragHoldMs = 100

    /// Clamp a caller-supplied hold to 0...maxHoldMs.
    static func clampHoldMs(_ ms: Int) -> Int {
        max(0, min(ms, maxHoldMs))
    }

    /// Click at screen coordinates. `count` posts that many consecutive click pairs
    /// with the `clickState` field set (1, 2, or 3) so AppKit treats them as a single
    /// click, double-click, or triple-click — used for word/line selection in text views.
    /// `button` picks the mouse button (left or right). `holdMs` keeps the last press down
    /// that long before releasing: a long-press (iOS context menus, Dock icon menus).
    static func click(
        x: Double,
        y: Double,
        count: Int = 1,
        button: MouseButton = .left,
        flags: CGEventFlags = [],
        holdMs: Double = 0
    ) async {
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

        // Modifier keys are held around the click (Device Hub forwards only those to the
        // device) and also set on the mouse events, which is where Mac apps read them.
        await withModifiers(flags) {
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

                // Set explicitly even when empty, so a plain click never inherits modifiers
                // the session believes are held.
                down?.flags = flags
                up?.flags = flags

                down?.post(tap: .cghidEventTap)
                await pause(i == clamped ? max(30, holdMs) : 30)
                up?.post(tap: .cghidEventTap)
                if i < clamped {
                    await pause(50) // inter-click gap, well under macOS's ~500ms double-click threshold
                }
            }
        }
        guard !flags.isEmpty else { return }
        // A flag-free mouse event resets the session's modifier state. The modifier key-ups
        // normally do, but Device Hub's Capture Keyboard swallows keyboard events, which left
        // the Shift a shift-click's mouse events carried held on the Mac.
        let reset = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: btn
        )
        reset?.flags = []
        reset?.post(tap: .cghidEventTap)
    }

    /// Press at the start point, move to the end point, release. `pressHoldMs` keeps the
    /// button still at the start before moving (~500ms+ is a long-press, which iOS
    /// drag-and-drop needs to lift an item). `steps`/`durationMs` pace the move (default:
    /// 10–40 moves, 10ms apart; `durationMs` 0 = default). `easeInOut` accelerates then
    /// slows to a stop instead of moving at constant speed, and `endHoldMs` keeps the button
    /// down at the end point first — both so a touch host sees the finger stop (see
    /// `scroll`'s drag mode).
    static func drag(
        fromX: Double,
        fromY: Double,
        toX: Double,
        toY: Double,
        pressHoldMs: Double = Double(defaultDragHoldMs),
        steps: Int? = nil,
        durationMs: UInt32 = 0,
        easeInOut: Bool = false,
        endHoldMs: Double = 0
    ) async {
        let dx = toX - fromX
        let dy = toY - fromY
        let distance = (dx * dx + dy * dy).squareRoot()
        let end = CGPoint(x: toX, y: toY)

        postMouseEvent(.leftMouseDown, at: CGPoint(x: fromX, y: fromY))
        await pause(pressHoldMs)

        let moveSteps = max(1, steps ?? max(10, min(40, Int(distance / 5))))
        let stepMs = durationMs > 0 ? Double(durationMs) / Double(moveSteps) : 10
        let dragInitThreshold = 6.0
        for i in 1...moveSteps {
            var t = Double(i) / Double(moveSteps)
            if easeInOut { t = t * t * (3 - 2 * t) } // smoothstep: zero speed at both ends
            if i == 1, distance > 0 {
                t = max(t, min(1.0, dragInitThreshold / distance))
            }
            postMouseEvent(.leftMouseDragged, at: CGPoint(x: fromX + dx * t, y: fromY + dy * t))
            await pause(stepMs)
        }

        for _ in 0..<Int(endHoldMs / 16) {
            postMouseEvent(.leftMouseDragged, at: end)
            await pause(16)
        }

        postMouseEvent(.leftMouseUp, at: end)
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

    struct CursorPoint: Encodable {
        let x: Int
        let y: Int
    }

    /// The OS-reported cursor position, rounded, and the system-wide AX element under it
    /// (nil over empty desktop). Read after `move` to confirm where the hover landed.
    static func cursorReadback() -> (cursor: CursorPoint?, element: AXNode?) {
        guard let location = CGEvent(source: nil)?.location else { return (nil, nil) }
        let cursor = CursorPoint(x: Int(location.x.rounded()), y: Int(location.y.rounded()))
        let element = try? AccessibilityManager.elementAtScreenPoint(x: location.x, y: location.y)
        return (cursor, element)
    }

    /// How long a drag-mode scroll holds the finger still before lifting, so iOS sees zero
    /// velocity and adds no momentum.
    private static let swipeHoldMs: Double = 120

    enum ScrollMode: String, Encodable {
        case wheel, drag
    }

    /// Scroll mode to use when the caller didn't pick one: `.drag` when the topmost
    /// window under the point belongs to a touch host, `.wheel` otherwise.
    static func defaultScrollMode(x: Int, y: Int) -> ScrollMode {
        let point = CGPoint(x: Double(x), y: Double(y))
        let top = onScreenWindowsFrontToBack().first(where: { $0.bounds.contains(point) })
        return scrollMode(forBundleID: top
            .flatMap { NSRunningApplication(processIdentifier: $0.pid)?.bundleIdentifier })
    }

    /// `.drag` for touch hosts (Device Hub, Simulator), `.wheel` for any other app or none.
    /// Device Hub ignores wheel scrolls unless Device > "Simulate Trackpad or Mouse" is on,
    /// and then reverses them; Simulator.app ignores them too. A finger drag works in both.
    static func scrollMode(forBundleID bundleID: String?) -> ScrollMode {
        guard let bundleID, TouchHost.bundleIDs.contains(bundleID) else { return .wheel }
        return .drag
    }

    /// Scroll at screen coordinates with the given mode. `.drag` swipes opposite the delta
    /// (dragging up scrolls content down), paced by steps/duration when given. It eases to a
    /// stop and holds the finger still before lifting: a touch that ends mid-motion makes iOS
    /// add momentum, so the content keeps going (often to its end) instead of following the
    /// finger.
    static func scroll(
        x: Int,
        y: Int,
        deltaX: Int32,
        deltaY: Int32,
        mode: ScrollMode,
        steps: Int = 1,
        durationMs: UInt32 = 0
    ) async {
        switch mode {
        case .drag:
            // Default to a calm swipe (~5ms per point, 0.3–1s): a fast one reads as a flick.
            let distance = (Double(deltaX) * Double(deltaX) + Double(deltaY) * Double(deltaY)).squareRoot()
            let duration = durationMs > 0 ? durationMs : UInt32(min(1000, max(300, distance * 5)))
            await drag(
                fromX: Double(x), fromY: Double(y),
                toX: Double(x) - Double(deltaX), toY: Double(y) - Double(deltaY),
                steps: steps > 1 ? steps : max(2, Int(duration) / 16),
                durationMs: duration,
                easeInOut: true,
                endHoldMs: swipeHoldMs
            )
        case .wheel:
            await scroll(
                x: Double(x), y: Double(y),
                deltaX: deltaX, deltaY: deltaY,
                steps: steps, durationMs: durationMs
            )
        }
    }

    /// Scroll-wheel at screen coordinates. Positive deltaY/deltaX scroll down/right.
    /// steps == 1 posts one instant event; steps > 1 (or durationMs) spreads the delta
    /// across a phased ease-in-out stream for smooth motion, preserving the total delta.
    private static func scroll(
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

    /// Type `text` key by key. Shift is held once across each run of characters that need
    /// it, like a typist, rather than pressed per capital (each press costs two modifier gaps).
    static func type(text: String, delayMs: UInt32 = 5) async {
        for run in shiftRuns(text) {
            let flags: CGEventFlags = run.shift ? .maskShift : []
            await withModifiers(flags) {
                for char in run.characters {
                    postKeyPress(KeyMapping.lookup(char).keyCode, flags: flags, text: String(char))
                    await pause(Double(delayMs))
                }
            }
        }
    }

    static func sendKey(keyCode: CGKeyCode, flags: CGEventFlags) async {
        await withModifiers(flags) {
            postKeyPress(keyCode, flags: flags)
        }
    }

    /// `text` split into consecutive runs of characters that all need Shift or all don't.
    static func shiftRuns(_ text: String) -> [(shift: Bool, characters: [Character])] {
        var runs: [(shift: Bool, characters: [Character])] = []
        for char in text {
            let shift = KeyMapping.lookup(char).shift
            if runs.last?.shift == shift {
                runs[runs.count - 1].characters.append(char)
            } else {
                runs.append((shift, [char]))
            }
        }
        return runs
    }

    /// One synthesized key event.
    struct KeyEvent: Equatable {
        let keyCode: CGKeyCode
        let isDown: Bool
        let flags: CGEventFlags
    }

    /// Modifier keys and their virtual key codes, in the order a hand presses them.
    private static let modifierKeys: [(flag: CGEventFlags, keyCode: CGKeyCode)] = [
        (.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55), (.maskSecondaryFn, 63)
    ]

    /// Key-downs for the modifier keys in `flags`, in press order, each carrying the
    /// modifiers held so far.
    static func modifierPresses(for flags: CGEventFlags) -> [KeyEvent] {
        var held: CGEventFlags = []
        return modifierKeys.filter { flags.contains($0.flag) }.map {
            held.insert($0.flag)
            return KeyEvent(keyCode: $0.keyCode, isDown: true, flags: held)
        }
    }

    /// Key-ups for the modifier keys in `flags`, in reverse press order. The last carries no
    /// flags, which releases the session's modifier state: a posted event that carries
    /// modifiers leaves the session believing they're held, so later synthetic keys and
    /// clicks would inherit them (shortcuts instead of text, cmd-clicks instead of clicks).
    static func modifierReleases(for flags: CGEventFlags) -> [KeyEvent] {
        var held = flags
        return modifierKeys.filter { flags.contains($0.flag) }.reversed().map {
            held.remove($0.flag)
            return KeyEvent(keyCode: $0.keyCode, isDown: false, flags: held)
        }
    }

    /// Hold the modifier keys in `flags` down around `body`, the way a real keyboard does.
    /// Flags on the key events alone aren't enough: Xcode's Device Hub forwards modifiers to
    /// the iOS device only from the modifier keys' own events, so ⌘A arrived as a plain "a".
    private static func withModifiers(_ flags: CGEventFlags, _ body: () async -> Void) async {
        for event in modifierPresses(for: flags) {
            post(event)
            await pause(modifierKeyGapMs)
        }
        await body()
        for event in modifierReleases(for: flags) {
            await pause(modifierKeyGapMs)
            post(event)
        }
    }

    /// Pause between a modifier key's event and the key's. Device Hub misses a modifier
    /// release posted in the same instant as the key-up, leaving ⌘ held on the iOS device
    /// (the next "x" became ⌘X).
    private static let modifierKeyGapMs: Double = 15

    /// Post a key's down and up. `text` is the character it types, independent of the
    /// keyboard layout.
    private static func postKeyPress(_ keyCode: CGKeyCode, flags: CGEventFlags, text: String? = nil) {
        post(KeyEvent(keyCode: keyCode, isDown: true, flags: flags), text: text)
        post(KeyEvent(keyCode: keyCode, isDown: false, flags: flags), text: text)
    }

    /// Post a single key event. Flags are set explicitly even when empty: inheriting a held
    /// cmd/option/control from the session would turn text into shortcuts.
    private static func post(_ key: KeyEvent, text: String? = nil) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: key.keyCode, keyDown: key.isDown)
        if let text {
            let utf16 = Array(text.utf16)
            event?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        }
        event?.flags = key.flags
        event?.post(tap: .cghidEventTap)
    }

    /// AX actions that only take visible effect when the target app is frontmost.
    /// `Press` works on backgrounded buttons because AX dispatches directly, but
    /// `ShowMenu` needs the app's event loop to render the popover.
    private static let focusRequiringActions: Set<String> = ["ShowMenu"]

    /// Returns true if the given AX action requires the target app to be FG to work.
    /// Accepts both `Press` and `AXPress` style names.
    private static func actionNeedsFocus(_ action: String) -> Bool {
        focusRequiringActions.contains(AXBridge.stripAXPrefix(action))
    }

    /// Perform an AX action on the first element matching the given filters, or on every
    /// match when `all` is set. Returns the matched nodes; throws `elementNotFound` if none.
    /// Auto-activates the target app only if the action is in `focusRequiringActions`.
    static func performAction(
        pid: pid_t,
        windowID: CGWindowID,
        action: String,
        filter: ElementFilter,
        all: Bool
    ) async throws -> [AXNode] {
        try PermissionManager.requireAccessibility()

        let window = try AccessibilityManager.resolveWindow(pid: pid, windowID: windowID)
        let matches = AccessibilityManager.findAll(in: window, filter: filter, limit: all ? nil : 1)

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

    /// `performAction`, then capture the result per `verify`: the post-action tree, or a
    /// before/after diff, taken `settleDelay` seconds after the action. Snapshots use
    /// `depth` or the full tree — a control's updated value (e.g. Calculator's display)
    /// often lives deeper than a shallow default would reach.
    static func performAndVerify(
        pid: pid_t,
        windowID: CGWindowID,
        action: String,
        filter: ElementFilter,
        all: Bool,
        verify: ActionVerifyMode,
        depth: Int?,
        settleDelay: TimeInterval
    ) async throws -> ActionOutcome {
        func snapshot() throws -> AXNode {
            try AccessibilityManager.inspect(pid: pid, windowID: windowID, maxDepth: depth)
        }

        let before = verify == .diff ? try snapshot().flattened : []
        let nodes = try await performAction(
            pid: pid, windowID: windowID, action: action, filter: filter, all: all
        )

        switch verify {
        case .none:
            return .performed(nodes, all: all)
        case .tree:
            try await Delay.seconds(settleDelay)
            return try .tree(ActionTreeResult(action: nodes, resultTree: snapshot()))
        case .diff:
            try await Delay.seconds(settleDelay)
            let after = try snapshot().flattened
            return .diff(ActionDiffResult(
                action: nodes,
                diff: TreeDiff(before: before, after: after)
            ))
        }
    }
}

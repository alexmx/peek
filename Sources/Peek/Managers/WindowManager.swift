import CoreGraphics
import Foundation
import ScreenCaptureKit
import Synchronization

enum WindowManager {
    private static let minWindowSize: CGFloat = 200

    private static let cacheTTL: TimeInterval = 0.3
    private static let cache = Mutex<(windows: [WindowInfo], timestamp: Date)?>(nil)

    private static func cachedSnapshot() -> [WindowInfo]? {
        cache.withLock { cached in
            if let cached, Date().timeIntervalSince(cached.timestamp) < cacheTTL {
                return cached.windows
            }
            return nil
        }
    }

    private static func storeSnapshot(_ windows: [WindowInfo]) {
        cache.withLock { $0 = (windows, Date()) }
    }

    static func invalidateCache() {
        cache.withLock { $0 = nil }
    }

    static func listWindows() async throws -> [WindowInfo] {
        if let cached = cachedSnapshot() { return cached }

        // Fast gate for the denied case. Not authoritative: preflight can report
        // granted while SCShareableContent still denies — fetchWindows handles that.
        guard CGPreflightScreenCaptureAccess() else {
            throw PeekError.screenCaptureNotGranted
        }

        let result = try await fetchWindows()
        storeSnapshot(result)
        return result
    }

    // MARK: - Private

    /// Per-attempt ceiling for the ScreenCaptureKit query.
    private static let shareableContentTimeout: TimeInterval = 5

    /// `SCShareableContent.excludingDesktopWindows` intermittently hangs (~49s) and ignores
    /// cancellation. Without serialization, repeated calls each abandon a hung query while it
    /// keeps a live `replayd` connection, stacking parallel hangs that pin `replayd`. This
    /// runs one detached query at a time (see `WindowQuery`), capping `replayd` to a single
    /// connection per process.
    private static let query = WindowQuery()

    private static func fetchWindows() async throws -> [WindowInfo] {
        try await query.run(timeout: shareableContentTimeout) {
            try await shareableWindows()
        }
    }

    /// Runs inside the detached query task: `SCShareableContent`/`SCWindow` aren't Sendable,
    /// but the returned `[WindowInfo]` is.
    private static func shareableWindows() async throws -> [WindowInfo] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: false
            )
            let onScreenIDs = onScreenWindowIDs()
            return content.windows.compactMap { scWindow -> WindowInfo? in
                guard let app = scWindow.owningApplication,
                      scWindow.windowLayer == 0 else { return nil }

                let frame = scWindow.frame
                guard frame.width > minWindowSize, frame.height > minWindowSize else { return nil }

                let title = scWindow.title ?? ""
                let isOnScreen = onScreenIDs.contains(scWindow.windowID)

                // Offscreen + no title = placeholder/staging window
                if !isOnScreen, title.isEmpty { return nil }

                // Skip AutoFill helper windows
                if app.applicationName.hasPrefix("AutoFill") { return nil }

                return WindowInfo(
                    windowID: scWindow.windowID,
                    ownerName: app.applicationName,
                    windowTitle: title,
                    pid: app.processID,
                    frame: frame,
                    isOnScreen: isOnScreen
                )
            }
        } catch let error as NSError where error.domain.contains("SCStream") {
            // ScreenCaptureKit denial (-3801).
            throw PeekError.screenCaptureNotGranted
        }
    }

    /// Coalesces callers onto one in-flight query. Each parks on a resume-once waiter,
    /// resumed by whichever comes first: the query completing (broadcast to all waiters) or
    /// its own timeout/cancellation. `running` stays true until the query *truly* finishes,
    /// so a caller timing out never re-spawns a query that's still wedged.
    private final class WindowQuery: Sendable {
        private struct Waiter {
            var cont: CheckedContinuation<[WindowInfo], Error>?
            var pending: Result<[WindowInfo], Error>?
        }

        private struct State {
            var running = false
            var waiters: [UUID: Waiter] = [:]
        }

        private let state = Mutex(State())

        func run(
            timeout: TimeInterval,
            _ body: @escaping @Sendable () async throws -> [WindowInfo]
        ) async throws -> [WindowInfo] {
            let id = UUID()
            let startQuery = state.withLock { s -> Bool in
                s.waiters[id] = Waiter()
                if s.running { return false }
                s.running = true
                return true
            }

            if startQuery {
                Task.detached(priority: .userInitiated) {
                    let result: Result<[WindowInfo], Error>
                    do {
                        result = try await .success(body())
                    } catch {
                        result = .failure(error)
                    }
                    self.broadcast(result)
                }
            }

            let timeoutTask = Task {
                try? await Delay.seconds(timeout)
                self.deliver(id, .failure(PeekError.captureFailed))
            }
            defer { timeoutTask.cancel() }

            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { cont in
                    self.attach(id, cont)
                }
            } onCancel: {
                self.deliver(id, .failure(CancellationError()))
            }
        }

        /// Park a caller's continuation, consuming a result that raced ahead of it.
        private func attach(_ id: UUID, _ cont: CheckedContinuation<[WindowInfo], Error>) {
            let pending: Result<[WindowInfo], Error>? = state.withLock { s in
                guard var w = s.waiters[id] else { return nil }
                if let p = w.pending {
                    s.waiters[id] = nil
                    return p
                }
                w.cont = cont
                s.waiters[id] = w
                return nil
            }
            if let pending { cont.resume(with: pending) }
        }

        /// Resume one waiter (timeout/cancellation). First delivery wins; buffered if the
        /// continuation hasn't attached yet.
        private func deliver(_ id: UUID, _ result: Result<[WindowInfo], Error>) {
            let cont: CheckedContinuation<[WindowInfo], Error>? = state.withLock { s in
                guard var w = s.waiters[id] else { return nil }
                if let c = w.cont {
                    s.waiters[id] = nil
                    return c
                }
                if w.pending == nil {
                    w.pending = result
                    s.waiters[id] = w
                }
                return nil
            }
            cont?.resume(with: result)
        }

        /// Query finished: clear `running` and resume every still-parked waiter.
        private func broadcast(_ result: Result<[WindowInfo], Error>) {
            let conts: [CheckedContinuation<[WindowInfo], Error>] = state.withLock { s in
                s.running = false
                var resumed: [CheckedContinuation<[WindowInfo], Error>] = []
                for (id, var w) in s.waiters {
                    if let c = w.cont {
                        resumed.append(c)
                        s.waiters[id] = nil
                    } else if w.pending == nil {
                        w.pending = result
                        s.waiters[id] = w
                    }
                }
                return resumed
            }
            for c in conts { c.resume(with: result) }
        }
    }

    /// On-screen window IDs via CGWindowList (lightweight, no permissions needed).
    private static func onScreenWindowIDs() -> Set<CGWindowID> {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }
        return Set(list.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
    }

    /// On-screen window IDs in front-to-back z-order (frontmost first), via CGWindowList.
    /// Used to resolve `--app`/`--pid` to the frontmost matching window.
    static func onScreenWindowIDsFrontToBack() -> [CGWindowID] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
    }
}

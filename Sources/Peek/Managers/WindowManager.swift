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

    /// Window list via ScreenCaptureKit, bounded by a timeout.
    ///
    /// `SCShareableContent.excludingDesktopWindows` intermittently hangs (~49s) leaking its
    /// continuation. A TaskGroup timeout can't bound it — the group awaits all children and
    /// the query ignores cancellation. So we run it detached and race a resume-once
    /// continuation: on hang the timeout resumes the caller and the detached task is
    /// abandoned. Mapping runs inside the task (SCShareableContent/SCWindow aren't Sendable).
    private static func fetchWindows() async throws -> [WindowInfo] {
        let box = FetchContinuation()

        let work = Task.detached(priority: .userInitiated) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true,
                    onScreenWindowsOnly: false
                )
                let onScreenIDs = onScreenWindowIDs()
                let windows = content.windows.compactMap { scWindow -> WindowInfo? in
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
                box.complete(.success(windows))
            } catch let error as NSError where error.domain.contains("SCStream") {
                // ScreenCaptureKit denial (-3801).
                box.complete(.failure(PeekError.screenCaptureNotGranted))
            } catch {
                box.complete(.failure(error))
            }
        }

        let timeout = Task {
            do {
                try await Delay.seconds(shareableContentTimeout)
                box.complete(.failure(PeekError.captureFailed))
            } catch {
                // Cancelled because the query already finished — nothing to do.
            }
        }
        defer { timeout.cancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                box.attach(cont)
            }
        } onCancel: {
            box.complete(.failure(CancellationError()))
            work.cancel()
        }
    }

    /// Resume-once race between the query, the timeout, and the awaiting continuation.
    /// First completion wins; a result arriving before `attach` is buffered, not dropped.
    private final class FetchContinuation: Sendable {
        private struct State {
            var cont: CheckedContinuation<[WindowInfo], Error>?
            var pending: Result<[WindowInfo], Error>?
            var done = false
        }

        private let state = Mutex(State())

        func attach(_ c: CheckedContinuation<[WindowInfo], Error>) {
            state.withLock { s in
                if let pending = s.pending {
                    s.done = true
                    c.resume(with: pending)
                } else {
                    s.cont = c
                }
            }
        }

        func complete(_ result: Result<[WindowInfo], Error>) {
            state.withLock { s in
                guard !s.done else { return }
                if let c = s.cont {
                    s.cont = nil
                    s.done = true
                    c.resume(with: result)
                } else if s.pending == nil {
                    s.pending = result // arrived before attach; first one wins
                }
            }
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
}

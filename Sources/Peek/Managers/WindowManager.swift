import CoreGraphics
import Foundation
import ScreenCaptureKit

enum WindowManager {
    private static let minWindowSize: CGFloat = 200

    private static let cacheTTL: TimeInterval = 0.3
    nonisolated(unsafe) private static var cache: (windows: [WindowInfo], timestamp: Date)?
    private static let cacheLock = NSLock()

    private static func cachedSnapshot() -> [WindowInfo]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache, Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.windows
        }
        return nil
    }

    private static func storeSnapshot(_ windows: [WindowInfo]) {
        cacheLock.lock()
        cache = (windows, Date())
        cacheLock.unlock()
    }

    static func invalidateCache() {
        cacheLock.lock()
        cache = nil
        cacheLock.unlock()
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
    /// `SCShareableContent.excludingDesktopWindows` intermittently leaks its internal
    /// `CheckedContinuation` and never resumes — its completion handler stops firing,
    /// and the framework only gives up tens of seconds later (observed ~49s). A
    /// `withThrowingTaskGroup` timeout does NOT help here: a task group awaits all of
    /// its children before returning, and `cancelAll()` only *requests* cancellation,
    /// which this query ignores — so the group blocks on the hung child anyway.
    ///
    /// Instead we run the query in a *detached* (unstructured) task and race it against
    /// a timeout through a resume-once continuation. If the query hangs, the timeout
    /// resumes the awaiting caller after `shareableContentTimeout` and the detached task
    /// is abandoned (it may still log a continuation-leak warning from inside SC, but it
    /// no longer blocks us). Mapping runs inside the detached task since
    /// SCShareableContent/SCWindow aren't Sendable.
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
                try await Task.sleep(nanoseconds: UInt64(shareableContentTimeout * 1_000_000_000))
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

    /// Resume-once mediator between the detached SCShareableContent task, the timeout
    /// task, and the awaiting continuation. Whichever completes first wins; results that
    /// arrive before the continuation is attached are buffered so none are dropped.
    private final class FetchContinuation: @unchecked Sendable {
        private let lock = NSLock()
        private var cont: CheckedContinuation<[WindowInfo], Error>?
        private var pending: Result<[WindowInfo], Error>?
        private var done = false

        func attach(_ c: CheckedContinuation<[WindowInfo], Error>) {
            lock.lock(); defer { lock.unlock() }
            if let pending {
                done = true
                c.resume(with: pending)
            } else {
                cont = c
            }
        }

        func complete(_ result: Result<[WindowInfo], Error>) {
            lock.lock(); defer { lock.unlock() }
            guard !done else { return }
            if let c = cont {
                cont = nil
                done = true
                c.resume(with: result)
            } else if pending == nil {
                pending = result // arrived before attach; first one wins
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

        var ids = Set<CGWindowID>()
        for entry in list {
            if let id = entry[kCGWindowNumber as String] as? CGWindowID {
                ids.insert(id)
            }
        }
        return ids
    }
}

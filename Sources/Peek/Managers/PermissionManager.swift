import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Synchronization

enum PermissionManager {
    static func requireAccessibility() throws {
        guard AXIsProcessTrusted() else {
            throw PeekError.accessibilityNotTrusted
        }
    }

    static func requireScreenCapture() throws {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw PeekError.screenCaptureNotGranted
        }
    }

    struct Status: Encodable {
        let accessibility: Bool
        let screenRecording: Bool
    }

    /// Check all permissions, optionally prompting for any that are missing.
    static func checkAll(prompt: Bool) async -> Status {
        let accessibility = prompt
            ? AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            : AXIsProcessTrusted()

        let screenRecording = await probeScreenCapture() == .works
        if !screenRecording, prompt {
            CGRequestScreenCaptureAccess()
        }

        return Status(accessibility: accessibility, screenRecording: screenRecording)
    }

    /// Outcome of a live ScreenCaptureKit probe. `denied` means the grant is actively refused
    /// (a stale positive from preflight); `inconclusive` means the query failed for another
    /// reason — e.g. a wedged/slow `replayd` — which is not a permission problem.
    enum ScreenCaptureProbe {
        case works, denied, inconclusive
    }

    /// Probe Screen Recording with a real ScreenCaptureKit query. `CGPreflightScreenCaptureAccess`
    /// can report granted while SCShareableContent denies — most commonly a stale grant after the
    /// host app updates.
    static func probeScreenCapture() async -> ScreenCaptureProbe {
        do {
            try await probeQuery.run(timeout: probeTimeout) {
                try await queryShareableContent()
            }
            return .works
        } catch PeekError.screenCaptureNotGranted {
            return .denied
        } catch {
            return .inconclusive
        }
    }

    /// Per-attempt ceiling for the ScreenCaptureKit probe.
    private static let probeTimeout: TimeInterval = 5

    /// `SCShareableContent.excludingDesktopWindows` intermittently hangs (~49s) and ignores
    /// cancellation. Running one detached query at a time (see `ProbeQuery`) caps `replayd`
    /// to a single connection per process. Only the probe uses ScreenCaptureKit — window
    /// listing goes through CGWindowList (see `WindowManager`).
    private static let probeQuery = ProbeQuery()

    /// One real ScreenCaptureKit query; the result itself is irrelevant. Throws
    /// `.screenCaptureNotGranted` on an active denial (-3801).
    private static func queryShareableContent() async throws {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        } catch let error as NSError where error.domain.contains("SCStream") {
            throw PeekError.screenCaptureNotGranted
        }
    }

    /// Coalesces callers onto one in-flight query. Each parks on a resume-once waiter,
    /// resumed by whichever comes first: the query completing (broadcast to all waiters) or
    /// its own timeout/cancellation. `running` stays true until the query *truly* finishes,
    /// so a caller timing out never re-spawns a query that's still wedged.
    private final class ProbeQuery: Sendable {
        private struct Waiter {
            var cont: CheckedContinuation<Void, Error>?
            var pending: Result<Void, Error>?
        }

        private struct State {
            var running = false
            var waiters: [UUID: Waiter] = [:]
        }

        private let state = Mutex(State())

        func run(timeout: TimeInterval, _ body: @escaping @Sendable () async throws -> Void) async throws {
            let id = UUID()
            let startQuery = state.withLock { s -> Bool in
                s.waiters[id] = Waiter()
                if s.running { return false }
                s.running = true
                return true
            }

            if startQuery {
                Task.detached(priority: .userInitiated) {
                    let result: Result<Void, Error>
                    do {
                        try await body()
                        result = .success(())
                    } catch {
                        result = .failure(error)
                    }
                    self.broadcast(result)
                }
            }

            let timeoutTask = Task {
                try? await Delay.seconds(timeout)
                self.deliver(id, .failure(PeekError.timeout("screen-recording probe", timeout)))
            }
            defer { timeoutTask.cancel() }

            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { cont in
                    self.attach(id, cont)
                }
            } onCancel: {
                self.deliver(id, .failure(CancellationError()))
            }
        }

        /// Park a caller's continuation, consuming a result that raced ahead of it.
        private func attach(_ id: UUID, _ cont: CheckedContinuation<Void, Error>) {
            let pending: Result<Void, Error>? = state.withLock { s in
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
        private func deliver(_ id: UUID, _ result: Result<Void, Error>) {
            let cont: CheckedContinuation<Void, Error>? = state.withLock { s in
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
        private func broadcast(_ result: Result<Void, Error>) {
            let conts: [CheckedContinuation<Void, Error>] = state.withLock { s in
                s.running = false
                var resumed: [CheckedContinuation<Void, Error>] = []
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
}

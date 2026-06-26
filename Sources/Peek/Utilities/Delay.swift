import Foundation

/// Sleep helpers expressed in milliseconds or seconds — keeps raw nanoseconds out of call sites.
enum Delay {
    /// Suspend for `ms` milliseconds, honoring cancellation (throws `CancellationError`).
    static func milliseconds(_ ms: Double) async throws {
        try await Task.sleep(for: .seconds(ms / 1000))
    }

    /// Suspend for `seconds`, honoring cancellation (throws `CancellationError`).
    static func seconds(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    /// Blocking sleep for synchronous contexts. Prefer the async variants; only for
    /// the rare sync retry loops that can't `await`.
    static func blockingMilliseconds(_ ms: Double) {
        usleep(UInt32((ms * 1000).rounded()))
    }
}

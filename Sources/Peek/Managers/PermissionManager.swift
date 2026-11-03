import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

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
    /// reason — e.g. a wedged/slow `replayd` — which is not a permission problem. The raw
    /// value is the probe subcommand's exit status.
    enum ScreenCaptureProbe: Int32 {
        case works = 0, inconclusive = 1, denied = 2

        /// The outcome a probe child reported: its exit status, or nil when it couldn't start or
        /// was killed. Anything unrecognised is inconclusive, never a false "denied".
        init(exitStatus: Int32?) {
            self = exitStatus.flatMap(Self.init(rawValue:)) ?? .inconclusive
        }
    }

    /// The hidden subcommand that runs the probe in a child process (`ScreenCaptureProbeCommand`).
    static let probeSubcommand = "screen-capture-probe"

    /// Probe Screen Recording with a real ScreenCaptureKit query. `CGPreflightScreenCaptureAccess`
    /// can report granted while ScreenCaptureKit denies — most commonly a stale grant after the
    /// host app updates. The query runs in a child peek (`ScreenCaptureProbeCommand`), never in
    /// this process (see `ChildProcess`); a child that hangs is killed after `probeTimeout`.
    static func probeScreenCapture() async -> ScreenCaptureProbe {
        guard let peek = Bundle.main.executableURL else { return .inconclusive }
        let status = await ChildProcess.run(peek, arguments: [probeSubcommand], timeout: probeTimeout)
        return ScreenCaptureProbe(exitStatus: status)
    }

    /// Longest the probe may take before its child process is killed.
    private static let probeTimeout: TimeInterval = 5

    /// The probe itself: one real ScreenCaptureKit query, whose result is irrelevant beyond
    /// succeeding. An active denial (-3801) surfaces as an SCStream-domain error. Only the probe
    /// subcommand may call this, in its own short-lived process; anywhere else (an MCP server)
    /// it brings back the `replayd` fight described in `ChildProcess`.
    static func queryScreenCaptureInProcess() async -> ScreenCaptureProbe {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            return .works
        } catch let error as NSError where error.domain.contains("SCStream") {
            return .denied
        } catch {
            return .inconclusive
        }
    }
}

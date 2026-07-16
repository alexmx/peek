import ApplicationServices
import CoreGraphics
import Foundation

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
    /// host app updates. Cache is cleared first so the result reflects current state.
    static func probeScreenCapture() async -> ScreenCaptureProbe {
        WindowManager.invalidateCache()
        do {
            _ = try await WindowManager.listWindows()
            return .works
        } catch PeekError.screenCaptureNotGranted {
            return .denied
        } catch {
            return .inconclusive
        }
    }
}

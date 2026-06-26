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

        let screenRecording = await probeScreenRecording()
        if !screenRecording, prompt {
            CGRequestScreenCaptureAccess()
        }

        return Status(accessibility: accessibility, screenRecording: screenRecording)
    }

    /// Whether Screen Recording actually works, via a real ScreenCaptureKit query.
    /// Preflight can report granted while SCShareableContent denies, so probe instead.
    /// Cache is cleared first so the result reflects current state.
    private static func probeScreenRecording() async -> Bool {
        WindowManager.invalidateCache()
        do {
            _ = try await WindowManager.listWindows()
            return true
        } catch {
            return false
        }
    }
}

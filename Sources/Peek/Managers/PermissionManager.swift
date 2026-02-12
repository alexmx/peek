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
    static func checkAll(prompt: Bool) -> Status {
        let accessibility: Bool
        if prompt {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            accessibility = AXIsProcessTrustedWithOptions(options)
        } else {
            accessibility = AXIsProcessTrusted()
        }

        let screenRecording = CGPreflightScreenCaptureAccess()
        if !screenRecording, prompt {
            CGRequestScreenCaptureAccess()
        }

        return Status(accessibility: accessibility, screenRecording: screenRecording)
    }
}

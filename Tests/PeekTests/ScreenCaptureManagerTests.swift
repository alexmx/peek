import CoreGraphics
import Foundation
@testable import peek
import Testing

@Suite("ScreenCaptureManager Tests")
struct ScreenCaptureManagerTests {
    /// The window-less-app sentinel (window ID 0) must be rejected with the actionable
    /// no-capturable-window error — before any permission check, so this holds everywhere.
    @Test
    func captureRejectsSentinelWindowID() async {
        do {
            _ = try await ScreenCaptureManager.capture(
                windowID: kCGNullWindowID,
                outputPath: "/tmp/peek-test-should-never-exist.png"
            )
            Issue.record("capture of the sentinel window ID should throw")
        } catch PeekError.noCapturableWindow {
            // Expected.
        } catch {
            Issue.record("expected noCapturableWindow, got \(error)")
        }
    }

    @Test
    func capturePNGDataRejectsSentinelWindowID() async {
        do {
            _ = try await ScreenCaptureManager.capturePNGData(windowID: kCGNullWindowID)
            Issue.record("capture of the sentinel window ID should throw")
        } catch PeekError.noCapturableWindow {
            // Expected.
        } catch {
            Issue.record("expected noCapturableWindow, got \(error)")
        }
    }
}

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ScreenCaptureManager {
    struct CaptureResult: Encodable {
        let path: String
        let width: Int
        let height: Int
    }

    /// Capture a window to a PNG file and return the result.
    static func capture(windowID: CGWindowID, outputPath: String, crop: CGRect? = nil) async throws -> CaptureResult {
        let image = try await captureImage(windowID: windowID, crop: crop)
        try writePNG(image, to: outputPath)
        return CaptureResult(path: outputPath, width: image.width, height: image.height)
    }

    /// Capture a window and return the PNG data in memory (no file written).
    static func capturePNGData(windowID: CGWindowID, crop: CGRect? = nil) async throws -> Data {
        try await encodePNG(captureImage(windowID: windowID, crop: crop))
    }

    /// Capture a window image, cropped to a window-relative rect when given. Failures map
    /// to an actionable error (window-less target, hidden window, stale permission).
    private static func captureImage(windowID: CGWindowID, crop: CGRect?) async throws -> CGImage {
        try requireCapturableWindowID(windowID)
        try PermissionManager.requireScreenCapture()

        guard let image = await captureWindowImage(windowID) else {
            throw await captureFailure(for: windowID)
        }
        guard let crop else { return image }
        return try cropImage(image, to: crop, windowID: windowID)
    }

    /// `--app`/`--pid` targeting of a window-less app resolves to the sentinel window ID 0
    /// (see `WindowTarget.findWindow`) — meaningful for AX commands that scope to the
    /// AXApplication root, but never capturable. Reject it with an actionable message
    /// instead of letting the capture fail with a misleading "off-screen/minimized" error.
    private static func requireCapturableWindowID(_ windowID: CGWindowID) throws {
        guard windowID != kCGNullWindowID else {
            throw PeekError.noCapturableWindow
        }
    }

    /// Crop a captured window image to a window-relative rect, scaling the rect by the
    /// image's Retina factor (actual pixels vs the window's point size). The point size comes
    /// from CGWindowList, which is synchronous and never goes through `replayd`.
    private static func cropImage(_ image: CGImage, to crop: CGRect, windowID: CGWindowID) throws -> CGImage {
        guard let frame = windowFrame(windowID) else {
            throw PeekError.windowNotFound(windowID)
        }
        let scaleX = CGFloat(image.width) / frame.width
        let scaleY = CGFloat(image.height) / frame.height
        let scaledRect = CGRect(
            x: crop.origin.x * scaleX,
            y: crop.origin.y * scaleY,
            width: crop.size.width * scaleX,
            height: crop.size.height * scaleY
        )
        guard let cropped = image.cropping(to: scaledRect) else {
            throw PeekError.invalidCropRegion
        }
        return cropped
    }

    /// A window's frame in points via CGWindowList — synchronous, no ScreenCaptureKit/`replayd`
    /// round-trip. Returns nil if the window no longer exists. Goes through
    /// `WindowManager.windowInfo(byID:)` because `.optionIncludingWindow` returns nothing
    /// for off-screen windows — and dismissed panels are still croppable captures.
    private static func windowFrame(_ windowID: CGWindowID) -> CGRect? {
        WindowManager.windowInfo(byID: windowID)?.frame
    }

    /// Longest a single window capture may take before the helper is killed.
    private static let captureTimeout: TimeInterval = 8

    /// Capture a window with the `screencapture` tool in a child process — never in peek's own
    /// process, see `ChildProcess`. It also reaches off-screen windows whose backing store
    /// persists, a dismissed MenuBarExtra panel being the canonical case. `-x` mutes the
    /// shutter sound, `-o` omits the window shadow. Uses the same Screen Recording grant and
    /// steals no focus.
    private static func captureWindowImage(_ windowID: CGWindowID) async -> CGImage? {
        guard WindowManager.windowInfo(byID: windowID) != nil else { return nil }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("peek-capture-\(windowID)-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let status = await ChildProcess.run(
            URL(fileURLWithPath: "/usr/sbin/screencapture"),
            arguments: ["-x", "-o", "-l", String(windowID), tempURL.path],
            timeout: captureTimeout
        )
        // Decode from in-memory data, not the file: CGImageSource images decode lazily,
        // and the temp file is deleted on return.
        guard status == 0,
              let data = try? Data(contentsOf: tempURL),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Distinguish "window is off-screen/hidden" and "stale Screen Recording grant" from a generic
    /// capture failure so callers get an actionable message. Hidden-window detection uses
    /// NSRunningApplication via the owning PID resolved from CGWindowList (synchronous).
    /// When the window is visible yet capture returned nil, `CGPreflightScreenCaptureAccess`
    /// has likely returned a stale positive (common after the host app updates), so we
    /// confirm with a real ScreenCaptureKit probe before reporting.
    private static func captureFailure(for windowID: CGWindowID) async -> PeekError {
        // .optionAll includes off-screen and minimized windows so we can find the entry
        // even when the owning app has been hidden.
        let records = WindowManager.windowRecords([.optionAll, .excludeDesktopElements])
        guard let record = records.first(where: { $0.windowID == windowID }) else {
            return await screenCaptureUnavailable() ?? PeekError.captureFailed
        }
        // CGWindowList omits kCGWindowIsOnscreen for off-screen windows, so nil means off-screen.
        if record.isOnScreen != true || record.alpha == 0 {
            return PeekError.windowHidden(windowID)
        }
        if NSRunningApplication(processIdentifier: record.pid)?.isHidden == true {
            return PeekError.windowHidden(windowID)
        }
        return await screenCaptureUnavailable() ?? PeekError.captureFailed
    }

    /// `.screenCaptureStale` only when a live probe *actively denies* access — the earlier
    /// preflight was a stale positive. A timeout or otherwise inconclusive probe (e.g. a
    /// wedged `replayd`) is not a permission problem, so return nil and let the caller
    /// report the generic `.captureFailed`.
    private static func screenCaptureUnavailable() async -> PeekError? {
        await PermissionManager.probeScreenCapture() == .denied ? PeekError.screenCaptureStale : nil
    }

    private static func encodePNG(_ image: CGImage) throws -> Data {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw PeekError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PeekError.encodingFailed
        }
        return mutableData as Data
    }

    private static func writePNG(_ image: CGImage, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw PeekError.failedToWrite(path)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PeekError.failedToWrite(path)
        }
    }
}

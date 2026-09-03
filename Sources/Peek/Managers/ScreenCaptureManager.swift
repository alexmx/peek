import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

enum ScreenCaptureManager {
    struct CaptureResult: Encodable {
        let path: String
        let width: Int
        let height: Int
    }

    /// Capture a window to a PNG file and return the result.
    static func capture(windowID: CGWindowID, outputPath: String, crop: CGRect? = nil) async throws -> CaptureResult {
        try requireCapturableWindowID(windowID)
        try PermissionManager.requireScreenCapture()

        guard var image = captureWindowImage(windowID) else {
            throw await captureFailure(for: windowID)
        }

        if let crop {
            image = try cropImage(image, to: crop, windowID: windowID)
        }

        try writePNG(image, to: outputPath)
        return CaptureResult(path: outputPath, width: image.width, height: image.height)
    }

    /// Capture a window and return the PNG data in memory (no file written).
    static func capturePNGData(
        windowID: CGWindowID,
        crop: CGRect? = nil
    ) async throws -> (data: Data, width: Int, height: Int) {
        try requireCapturableWindowID(windowID)
        try PermissionManager.requireScreenCapture()

        guard var image = captureWindowImage(windowID) else {
            throw await captureFailure(for: windowID)
        }

        if let crop {
            image = try cropImage(image, to: crop, windowID: windowID)
        }

        let data = try encodePNG(image)
        return (data, image.width, image.height)
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
    /// from CGWindowList — the same source as the capture itself, and synchronous, so it can't
    /// hang on a wedged `replayd` the way `SCShareableContent` can.
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

    /// CGWindowListCreateImage is deprecated in macOS 15 but still works at runtime —
    /// for on-screen windows only (see `screencaptureFallback` for the off-screen case).
    /// ScreenCaptureKit (SCScreenshotManager/SCStream) requires a RunLoop and hangs in CLI tools.
    @_silgen_name("CGWindowListCreateImage")
    private static func _CGWindowListCreateImage(
        _ screenBounds: CGRect,
        _ listOption: CGWindowListOption,
        _ windowID: CGWindowID,
        _ imageOption: CGWindowImageOption
    ) -> CGImage?

    private static func captureWindowImage(_ windowID: CGWindowID) -> CGImage? {
        if let image = _CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) {
            return image
        }
        return screencaptureFallback(windowID)
    }

    /// On macOS 15 the CG capture path returns nil for off-screen windows, but their
    /// backing stores persist and stay capturable — a dismissed MenuBarExtra panel being
    /// the canonical case. `screencapture -l` (ScreenCaptureKit-based) reaches them, so
    /// shell out to it rather than SCScreenshotManager: building an SCContentFilter needs
    /// SCShareableContent, whose `replayd` wedges peek deliberately moved away from.
    /// `-x` mutes the shutter sound, `-o` omits the window shadow to match the CG path's
    /// `boundsIgnoreFraming`. Uses the same Screen Recording grant; steals no focus.
    private static func screencaptureFallback(_ windowID: CGWindowID) -> CGImage? {
        guard windowID != kCGNullWindowID,
              WindowManager.windowInfo(byID: windowID) != nil else { return nil }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("peek-capture-\(windowID)-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(windowID), tempURL.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        // Decode from in-memory data, not the file: CGImageSource images decode lazily,
        // and the temp file is deleted on return.
        guard process.terminationStatus == 0,
              let data = try? Data(contentsOf: tempURL),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Distinguish "window is hidden" and "stale Screen Recording grant" from a generic
    /// capture failure so callers get an actionable message. Hidden-window detection uses
    /// NSRunningApplication via the owning PID resolved from CGWindowList (synchronous).
    /// When the window is visible yet capture returned nil, `CGPreflightScreenCaptureAccess`
    /// has likely returned a stale positive (common after the host app updates), so we
    /// confirm with a real ScreenCaptureKit probe before reporting.
    private static func captureFailure(for windowID: CGWindowID) async -> PeekError {
        // .optionAll includes off-screen and minimized windows so we can find the entry
        // even when the owning app has been hidden.
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]],
              let info = windows.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID })
        else {
            return await screenCaptureUnavailable() ?? PeekError.captureFailed
        }
        let onScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? true
        let alpha = info[kCGWindowAlpha as String] as? Double ?? 1.0
        if !onScreen || alpha == 0 {
            return PeekError.windowHidden(windowID)
        }
        if let pid = info[kCGWindowOwnerPID as String] as? Int32,
           let app = NSRunningApplication(processIdentifier: pid),
           app.isHidden {
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

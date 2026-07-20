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
    /// round-trip. Returns nil if the window no longer exists.
    private static func windowFrame(_ windowID: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let bounds = list.first?[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else {
            return nil
        }
        return frame
    }

    /// CGWindowListCreateImage is deprecated in macOS 15 but still works at runtime.
    /// ScreenCaptureKit (SCScreenshotManager/SCStream) requires a RunLoop and hangs in CLI tools.
    @_silgen_name("CGWindowListCreateImage")
    private static func _CGWindowListCreateImage(
        _ screenBounds: CGRect,
        _ listOption: CGWindowListOption,
        _ windowID: CGWindowID,
        _ imageOption: CGWindowImageOption
    ) -> CGImage?

    private static func captureWindowImage(_ windowID: CGWindowID) -> CGImage? {
        _CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        )
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

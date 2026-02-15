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
            throw PeekError.captureFailed
        }

        if let crop {
            // Compute Retina scale from actual image vs window point size
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                throw PeekError.windowNotFound(windowID)
            }
            let scaleX = CGFloat(image.width) / scWindow.frame.width
            let scaleY = CGFloat(image.height) / scWindow.frame.height
            let scaledRect = CGRect(
                x: crop.origin.x * scaleX,
                y: crop.origin.y * scaleY,
                width: crop.size.width * scaleX,
                height: crop.size.height * scaleY
            )
            guard let cropped = image.cropping(to: scaledRect) else {
                throw PeekError.invalidCropRegion
            }
            image = cropped
        }

        try writePNG(image, to: outputPath)
        return CaptureResult(path: outputPath, width: image.width, height: image.height)
    }

    // CGWindowListCreateImage is deprecated in macOS 15 but still works at runtime.
    // ScreenCaptureKit (SCScreenshotManager/SCStream) requires a RunLoop and hangs in CLI tools.
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

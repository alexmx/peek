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
        try PermissionManager.requireScreenCapture()

        guard var image = captureWindowImage(windowID) else {
            throw PeekError.windowNotFound(windowID)
        }

        if let crop {
            // Scale crop rect to account for Retina (image pixels vs point coordinates)
            let bounds = try await WindowManager.windowBounds(forWindowID: windowID)
            let scaleX = CGFloat(image.width) / CGFloat(bounds?.width ?? CGFloat(image.width))
            let scaleY = CGFloat(image.height) / CGFloat(bounds?.height ?? CGFloat(image.height))
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

        let url = URL(fileURLWithPath: outputPath)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw PeekError.failedToWrite(outputPath)
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw PeekError.failedToWrite(outputPath)
        }

        return CaptureResult(path: outputPath, width: image.width, height: image.height)
    }

    // CGWindowListCreateImage is marked unavailable in macOS 15 SDK but still works at runtime.
    // SCScreenshotManager requires a window server connection that CLI tools don't always have.
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
}

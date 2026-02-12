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

    static func capture(windowID: CGWindowID, outputPath: String, format: OutputFormat) throws {
        try PermissionManager.requireScreenCapture()

        guard let image = captureWindowImage(windowID) else {
            throw PeekError.windowNotFound(windowID)
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

        if format == .json {
            try printJSON(CaptureResult(path: outputPath, width: image.width, height: image.height))
        } else {
            print("Saved screenshot to \(outputPath)")
            print("Size: \(image.width)x\(image.height) pixels")
        }
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

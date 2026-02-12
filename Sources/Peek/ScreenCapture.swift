import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

enum ScreenCapture {
    struct CaptureResult: Encodable {
        let path: String
        let width: Int
        let height: Int
    }

    static func capture(windowID: CGWindowID, outputPath: String, json: Bool) async throws {
        // Get all available windows
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        // Find the window matching the CGWindowID
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw PeekError.windowNotFound(windowID)
        }

        // Create a content filter for this specific window
        let filter = SCContentFilter(desktopIndependentWindow: window)

        // Configure capture settings
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width)
        configuration.height = Int(window.frame.height)
        configuration.showsCursor = false

        // Capture the image
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)

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

        if json {
            try printJSON(CaptureResult(path: outputPath, width: image.width, height: image.height))
        } else {
            print("Saved screenshot to \(outputPath)")
            print("Size: \(image.width)x\(image.height) pixels")
        }
    }
}

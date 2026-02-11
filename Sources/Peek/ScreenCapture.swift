import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ScreenCapture {
    static func capture(windowID: CGWindowID, outputPath: String) throws {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
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

        print("Saved screenshot to \(outputPath)")
        print("Size: \(image.width)x\(image.height) pixels")
    }
}

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ScreenCapture {
    struct CaptureResult: Encodable {
        let path: String
        let width: Int
        let height: Int
    }

    static func capture(windowID: CGWindowID, outputPath: String, json: Bool) throws {
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

        if json {
            let result = CaptureResult(path: outputPath, width: image.width, height: image.height)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(result)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Saved screenshot to \(outputPath)")
            print("Size: \(image.width)x\(image.height) pixels")
        }
    }
}

import ArgumentParser
import Foundation

struct CaptureCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture",
        abstract: "Capture a screenshot of a window"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .shortAndLong, help: "Output file path (default: window_<id>.png)")
    var output: String?

    @Option(name: .long, help: "Crop region X offset (window-relative pixels)")
    var x: Int?

    @Option(name: .long, help: "Crop region Y offset (window-relative pixels)")
    var y: Int?

    @Option(name: .long, help: "Crop region width")
    var width: Int?

    @Option(name: .long, help: "Crop region height")
    var height: Int?

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func validate() throws {
        let parts = [x, y, width, height]
        let provided = parts.compactMap { $0 }.count
        if provided != 0 && provided != 4 {
            throw ValidationError("Crop requires all four options: --x, --y, --width, --height")
        }
    }

    func run() async throws {
        let resolved = try await target.resolve()
        let path = output ?? "window_\(resolved.windowID).png"
        let crop: CGRect? = if let x, let y, let width, let height {
            CGRect(x: x, y: y, width: width, height: height)
        } else {
            nil
        }
        let result = try await ScreenCaptureManager.capture(windowID: resolved.windowID, outputPath: path, crop: crop)
        switch format {
        case .json:
            try printJSON(result)
        case .toon:
            try printTOON(result)
        case .default:
            print("Saved \(result.path) (\(result.width)x\(result.height) pixels)")
        }
    }
}

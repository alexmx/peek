import ArgumentParser
import Foundation

struct CaptureCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture",
        abstract: "Capture a screenshot of a window"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .shortAndLong, help: "Output file path (default: window_<id>.png)")
    var output: String?

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func run() throws {
        let windowID = try target.resolve()
        let path = output ?? "window_\(windowID).png"
        try ScreenCaptureManager.capture(windowID: windowID, outputPath: path, format: format)
    }
}

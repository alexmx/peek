import ArgumentParser
import Foundation

struct CaptureCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture",
        abstract: "Capture a screenshot of a window"
    )

    @Argument(help: "The window ID to capture")
    var windowID: UInt32

    @Option(name: .shortAndLong, help: "Output file path (default: window_<id>.png)")
    var output: String?

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    func run() async throws {
        let path = output ?? "window_\(windowID).png"
        try await ScreenCapture.capture(windowID: windowID, outputPath: path, json: json)
    }
}

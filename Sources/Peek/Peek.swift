import ArgumentParser
import CoreGraphics

@main
struct Peek: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "macOS Window Inspector",
        subcommands: [List.self, Capture.self, Inspect.self]
    )
}

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all open windows"
    )

    func run() async throws {
        let windows = try await WindowManager.listWindows()
        WindowManager.printWindowList(windows)
    }
}

struct Capture: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Capture a screenshot of a window"
    )

    @Argument(help: "The window ID to capture")
    var windowID: UInt32

    @Option(name: .shortAndLong, help: "Output file path (default: window_<id>.png)")
    var output: String?

    func run() throws {
        let path = output ?? "window_\(windowID).png"
        try ScreenCapture.capture(windowID: windowID, outputPath: path)
    }
}

struct Inspect: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inspect the accessibility tree of a window"
    )

    @Argument(help: "The window ID to inspect")
    var windowID: UInt32

    func run() throws {
        guard let pid = WindowManager.pid(forWindowID: windowID) else {
            throw PeekError.windowNotFound(windowID)
        }
        try AccessibilityTree.inspect(pid: pid, windowID: windowID)
    }
}

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

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    func run() async throws {
        let windows = try await WindowManager.listWindows()
        if json {
            try WindowManager.printWindowListJSON(windows)
        } else {
            WindowManager.printWindowList(windows)
        }
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

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    func run() throws {
        let path = output ?? "window_\(windowID).png"
        try ScreenCapture.capture(windowID: windowID, outputPath: path, json: json)
    }
}

struct Inspect: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inspect the accessibility tree of a window"
    )

    @Argument(help: "The window ID to inspect")
    var windowID: UInt32

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    func run() throws {
        guard let pid = WindowManager.pid(forWindowID: windowID) else {
            throw PeekError.windowNotFound(windowID)
        }
        try AccessibilityTree.inspect(pid: pid, windowID: windowID, json: json)
    }
}

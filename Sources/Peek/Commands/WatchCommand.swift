import ArgumentParser
import CoreGraphics
import Foundation

struct WatchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Watch a window for accessibility changes in real-time"
    )

    @Argument(help: "The window ID to watch")
    var windowID: UInt32

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func run() throws {
        guard let pid = WindowManager.pid(forWindowID: windowID) else {
            throw PeekError.windowNotFound(windowID)
        }
        try MonitorManager.watch(pid: pid, windowID: windowID, format: format)
    }
}

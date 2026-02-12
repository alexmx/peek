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

    @Flag(name: .long, help: "Output as JSON (one event per line)")
    var json = false

    func run() throws {
        guard let pid = WindowManager.pid(forWindowID: windowID) else {
            throw PeekError.windowNotFound(windowID)
        }
        try Monitor.watch(pid: pid, windowID: windowID, json: json)
    }
}

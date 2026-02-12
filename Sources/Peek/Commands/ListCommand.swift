import ArgumentParser
import CoreGraphics
import Foundation

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all open windows"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    func run() async throws {
        let windows = try await WindowManager.listWindows()
        if json {
            try printJSON(windows)
        } else {
            printWindowList(windows)
        }
    }

    private func printWindowList(_ windows: [WindowInfo]) {
        if windows.isEmpty {
            print("No windows found.")
            return
        }

        let header = "ID".padding(toLength: 8, withPad: " ", startingAt: 0)
            + "PID".padding(toLength: 8, withPad: " ", startingAt: 0)
            + "App".padding(toLength: 26, withPad: " ", startingAt: 0)
            + "Title".padding(toLength: 31, withPad: " ", startingAt: 0)
            + "Frame"
        print(header)
        print(String(repeating: "-", count: 110))

        for w in windows {
            let title = w.windowTitle.isEmpty ? "(untitled)" : w.windowTitle
            let app = String(w.ownerName.prefix(25)).padding(toLength: 26, withPad: " ", startingAt: 0)
            let ttl = String(title.prefix(30)).padding(toLength: 31, withPad: " ", startingAt: 0)
            let id = "\(w.windowID)".padding(toLength: 8, withPad: " ", startingAt: 0)
            let pid = "\(w.pid)".padding(toLength: 8, withPad: " ", startingAt: 0)
            let frameStr = "(\(Int(w.frame.origin.x)), \(Int(w.frame.origin.y))) \(Int(w.frame.width))x\(Int(w.frame.height))"
            let onScreen = w.isOnScreen ? "" : " [offscreen]"

            print("\(id)\(pid)\(app)\(ttl)\(frameStr)\(onScreen)")
        }

        print("\n\(windows.count) window(s) found.")
    }
}

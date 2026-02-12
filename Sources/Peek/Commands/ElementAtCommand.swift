import ArgumentParser
import CoreGraphics
import Foundation

struct ElementAtCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "element-at",
        abstract: "Find the UI element at a screen coordinate"
    )

    @Argument(help: "The window ID to query")
    var windowID: UInt32

    @Argument(help: "X coordinate")
    var x: Int

    @Argument(help: "Y coordinate")
    var y: Int

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    func run() throws {
        guard let pid = WindowManager.pid(forWindowID: windowID) else {
            throw PeekError.windowNotFound(windowID)
        }

        guard let node = try AccessibilityTree.elementAt(
            pid: pid,
            windowID: windowID,
            x: x,
            y: y
        ) else {
            print("No element found at (\(x), \(y)).")
            return
        }

        if json {
            try printJSON(node)
        } else {
            var line = node.role
            if let t = node.title, !t.isEmpty { line += "  \"\(t)\"" }
            if let v = node.value, !v.isEmpty { line += "  value=\"\(v)\"" }
            if let d = node.description, !d.isEmpty { line += "  desc=\"\(d)\"" }
            if let f = node.frame {
                line += "  (\(f.x), \(f.y)) \(f.width)x\(f.height)"
            }
            print(line)
        }
    }
}

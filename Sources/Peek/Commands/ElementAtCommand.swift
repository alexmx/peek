import ArgumentParser
import CoreGraphics
import Foundation

struct ElementAtCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "element-at",
        abstract: "Hit-test: find the deepest UI element at a screen coordinate",
        discussion: "Returns the most specific (deepest) accessibility element at the given (x, y) screen point within the target window. Useful for identifying what lies under a cursor position or a known pixel coordinate."
    )

    @Argument(help: "The window ID to query")
    var windowID: UInt32

    @Argument(help: "X screen coordinate (pixels from left edge)")
    var x: Int

    @Argument(help: "Y screen coordinate (pixels from top edge)")
    var y: Int

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func run() throws {
        guard let pid = WindowManager.pid(forWindowID: windowID) else {
            throw PeekError.windowNotFound(windowID)
        }

        guard let node = try AccessibilityTreeManager.elementAt(
            pid: pid,
            windowID: windowID,
            x: x,
            y: y
        ) else {
            print("No element found at (\(x), \(y)).")
            return
        }

        if format == .json {
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

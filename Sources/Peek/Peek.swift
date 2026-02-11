import ArgumentParser
import CoreGraphics
import Foundation

@main
struct Peek: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "macOS Window Inspector",
        subcommands: [
            List.self, Capture.self, Inspect.self,
            Find.self, ElementAt.self,
            Click.self, Type.self, Action.self,
        ]
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

struct Find: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search for UI elements in a window"
    )

    @Argument(help: "The window ID to search")
    var windowID: UInt32

    @Option(name: .long, help: "Filter by role (e.g. AXButton, AXStaticText)")
    var role: String?

    @Option(name: .long, help: "Filter by title (case-insensitive substring)")
    var title: String?

    @Option(name: .long, help: "Filter by value (case-insensitive substring)")
    var value: String?

    @Option(name: .long, help: "Filter by description (case-insensitive substring)")
    var desc: String?

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    func validate() throws {
        if role == nil && title == nil && value == nil && desc == nil {
            throw ValidationError("At least one filter is required: --role, --title, --value, or --desc")
        }
    }

    func run() throws {
        guard let pid = WindowManager.pid(forWindowID: windowID) else {
            throw PeekError.windowNotFound(windowID)
        }

        let results = try AccessibilityTree.find(
            pid: pid,
            windowID: windowID,
            role: role,
            title: title,
            value: value,
            description: desc
        )

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(results)
            print(String(data: data, encoding: .utf8)!)
        } else {
            if results.isEmpty {
                print("No matching elements found.")
            } else {
                for node in results {
                    var line = node.role
                    if let t = node.title, !t.isEmpty { line += "  \"\(t)\"" }
                    if let v = node.value, !v.isEmpty { line += "  value=\"\(v)\"" }
                    if let d = node.description, !d.isEmpty { line += "  desc=\"\(d)\"" }
                    if let f = node.frame {
                        line += "  (\(f.x), \(f.y)) \(f.width)x\(f.height)"
                    }
                    print(line)
                }
                print("\n\(results.count) element(s) found.")
            }
        }
    }
}

struct ElementAt: ParsableCommand {
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
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(node)
            print(String(data: data, encoding: .utf8)!)
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

struct Click: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Click at screen coordinates"
    )

    @Argument(help: "X coordinate")
    var x: Double

    @Argument(help: "Y coordinate")
    var y: Double

    func run() {
        Interaction.click(x: x, y: y)
        print("Clicked at (\(Int(x)), \(Int(y)))")
    }
}

struct Type: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type",
        abstract: "Type text via keyboard events"
    )

    @Argument(help: "The text to type")
    var text: String

    func run() {
        Interaction.type(text: text)
        print("Typed \(text.count) character(s)")
    }
}

struct Action: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Perform an accessibility action on a UI element"
    )

    @Argument(help: "The window ID containing the element")
    var windowID: UInt32

    @Argument(help: "The AX action to perform (e.g. AXPress, AXConfirm, AXCancel, AXShowMenu)")
    var action: String

    @Option(name: .long, help: "Filter by role (e.g. AXButton)")
    var role: String?

    @Option(name: .long, help: "Filter by title (case-insensitive substring)")
    var title: String?

    @Option(name: .long, help: "Filter by value (case-insensitive substring)")
    var value: String?

    @Option(name: .long, help: "Filter by description (case-insensitive substring)")
    var desc: String?

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    func validate() throws {
        if role == nil && title == nil && value == nil && desc == nil {
            throw ValidationError("At least one filter is required: --role, --title, --value, or --desc")
        }
    }

    func run() throws {
        guard let pid = WindowManager.pid(forWindowID: windowID) else {
            throw PeekError.windowNotFound(windowID)
        }

        let node = try Interaction.performAction(
            pid: pid,
            windowID: windowID,
            action: action,
            role: role,
            title: title,
            value: value,
            description: desc
        )

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(node)
            print(String(data: data, encoding: .utf8)!)
        } else {
            var line = "Performed '\(action)' on: \(node.role)"
            if let t = node.title, !t.isEmpty { line += "  \"\(t)\"" }
            if let v = node.value, !v.isEmpty { line += "  value=\"\(v)\"" }
            if let d = node.description, !d.isEmpty { line += "  desc=\"\(d)\"" }
            print(line)
        }
    }
}

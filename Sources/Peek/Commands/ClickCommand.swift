import ArgumentParser
import Foundation

struct ClickCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click at screen coordinates"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .long, help: "X screen coordinate")
    var x: Int

    @Option(name: .long, help: "Y screen coordinate")
    var y: Int

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    struct ClickResult: Encodable {
        let x: Int
        let y: Int
    }

    func run() async throws {
        if target.windowID != nil || target.app != nil || target.pid != nil {
            let resolved = try await target.resolve()
            _ = try InteractionManager.activate(pid: resolved.pid, windowID: resolved.windowID)
            usleep(200_000) // 200ms for the window to fully come to foreground
        }

        InteractionManager.click(x: Double(x), y: Double(y))

        if format == .json {
            try printJSON(ClickResult(x: x, y: y))
        } else {
            print("Clicked at (\(x), \(y))")
        }
    }
}

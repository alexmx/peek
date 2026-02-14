import ArgumentParser
import Foundation

struct ClickCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click at screen coordinates"
    )

    @Argument(help: "X coordinate")
    var x: Int

    @Argument(help: "Y coordinate")
    var y: Int

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    struct ClickResult: Encodable {
        let x: Int
        let y: Int
    }

    func run() throws {
        InteractionManager.click(x: Double(x), y: Double(y))

        if format == .json {
            try printJSON(ClickResult(x: x, y: y))
        } else {
            print("Clicked at (\(x), \(y))")
        }
    }
}

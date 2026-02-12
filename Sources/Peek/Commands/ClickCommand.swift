import ArgumentParser
import Foundation

struct ClickCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click at screen coordinates"
    )

    @Argument(help: "X coordinate")
    var x: Double

    @Argument(help: "Y coordinate")
    var y: Double

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    struct ClickResult: Encodable {
        let x: Int
        let y: Int
    }

    func run() throws {
        InteractionManager.click(x: x, y: y)

        if format == .json {
            try printJSON(ClickResult(x: Int(x), y: Int(y)))
        } else {
            print("Clicked at (\(Int(x)), \(Int(y)))")
        }
    }
}

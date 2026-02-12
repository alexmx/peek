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

    func run() {
        Interaction.click(x: x, y: y)
        print("Clicked at (\(Int(x)), \(Int(y)))")
    }
}

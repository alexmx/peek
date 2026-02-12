import ArgumentParser
import Foundation

struct TypeCommand: ParsableCommand {
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

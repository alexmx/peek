import ArgumentParser
import Foundation

struct TypeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type",
        abstract: "Type text via keyboard events"
    )

    @Argument(help: "The text to type")
    var text: String

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    struct TypeResult: Encodable {
        let characters: Int
    }

    func run() throws {
        InteractionManager.type(text: text)

        if format == .json {
            try printJSON(TypeResult(characters: text.count))
        } else {
            print("Typed \(text.count) character(s)")
        }
    }
}

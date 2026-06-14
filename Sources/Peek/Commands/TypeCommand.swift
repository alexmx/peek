import ArgumentParser
import Foundation

struct TypeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type",
        abstract: "Type text via keyboard events"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .long, help: "The text to type")
    var text: String

    @Option(
        name: .long,
        help: "Per-character delay in milliseconds (default: 5). Bump to 10-20 if a lazy text field drops or duplicates characters."
    )
    var delayMs: UInt32 = 5

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    struct TypeResult: Encodable {
        let characters: Int
    }

    func run() async throws {
        if target.windowID != nil || target.app != nil || target.pid != nil {
            let resolved = try await target.resolve()
            _ = try await InteractionManager.activate(pid: resolved.pid, windowID: resolved.windowID)
        }

        InteractionManager.type(text: text, delayMs: delayMs)

        switch format {
        case .json:
            try printJSON(TypeResult(characters: text.count))
        case .toon:
            try printTOON(TypeResult(characters: text.count))
        case .default:
            print("Typed \(text.count) character(s)")
        }
    }
}

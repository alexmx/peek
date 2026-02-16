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

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    struct TypeResult: Encodable {
        let characters: Int
    }

    func run() async throws {
        if target.windowID != nil || target.app != nil || target.pid != nil {
            let resolved = try await target.resolve()
            _ = try InteractionManager.activate(pid: resolved.pid, windowID: resolved.windowID)
            usleep(200_000) // 200ms for the window to fully come to foreground
        }

        InteractionManager.type(text: text)

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

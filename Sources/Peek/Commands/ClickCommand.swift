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

    @Option(name: .long, help: "Click count: 1 (single), 2 (double — selects word in text views), 3 (triple — selects line). Default 1.")
    var count: Int = 1

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    struct ClickResult: Encodable {
        let x: Int
        let y: Int
        let count: Int
    }

    func run() async throws {
        if target.windowID != nil || target.app != nil || target.pid != nil {
            let resolved = try await target.resolve()
            _ = try await InteractionManager.activate(pid: resolved.pid, windowID: resolved.windowID)
        }

        InteractionManager.click(x: Double(x), y: Double(y), count: count)

        let result = ClickResult(x: x, y: y, count: max(1, min(count, 3)))
        switch format {
        case .json:
            try printJSON(result)
        case .toon:
            try printTOON(result)
        case .default:
            let label = ["single", "double", "triple"][result.count - 1]
            print("\(label.capitalized)-clicked at (\(x), \(y))")
        }
    }
}

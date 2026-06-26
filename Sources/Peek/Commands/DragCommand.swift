import ArgumentParser
import Foundation

struct DragCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "drag",
        abstract: "Drag from one screen point to another"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .long, help: "Source X screen coordinate")
    var fromX: Int

    @Option(name: .long, help: "Source Y screen coordinate")
    var fromY: Int

    @Option(name: .long, help: "Destination X screen coordinate")
    var toX: Int

    @Option(name: .long, help: "Destination Y screen coordinate")
    var toY: Int

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    struct DragResult: Encodable {
        let fromX: Int
        let fromY: Int
        let toX: Int
        let toY: Int
    }

    func run() async throws {
        if let resolved = try await target.activateIfSpecified() {
            try await InteractionManager.ensureOnTarget(
                points: [(fromX, fromY), (toX, toY)], pid: resolved.pid, windowID: target.windowID
            )
        }

        await InteractionManager.drag(
            fromX: Double(fromX), fromY: Double(fromY),
            toX: Double(toX), toY: Double(toY)
        )

        let result = DragResult(fromX: fromX, fromY: fromY, toX: toX, toY: toY)
        try emit(result, as: format) {
            print("Dragged (\(fromX), \(fromY)) → (\(toX), \(toY))")
        }
    }
}

import ArgumentParser
import Foundation

struct DragCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "drag",
        abstract: "Drag from one screen point to another"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .long, parsing: .unconditional, help: "Source X screen coordinate")
    var fromX: Int

    @Option(name: .long, parsing: .unconditional, help: "Source Y screen coordinate")
    var fromY: Int

    @Option(name: .long, parsing: .unconditional, help: "Destination X screen coordinate")
    var toX: Int

    @Option(name: .long, parsing: .unconditional, help: "Destination Y screen coordinate")
    var toY: Int

    @Option(
        name: .long,
        help: "Hold the press still this many ms before moving (max 5000). ~500+ is a long-press, which iOS drag-and-drop needs to lift an item."
    )
    var holdMs: Int = InteractionManager.defaultDragHoldMs

    @Option(name: .long, help: "Number of intermediate moves along the path (default 10-40, by distance)")
    var steps: Int?

    @Option(name: .long, help: "Wall-clock duration in ms of the move (0 = 10ms per step). Pairs with --steps")
    var durationMs: Int = 0

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func run() async throws {
        try await target.activateAndGuard([(fromX, fromY), (toX, toY)])

        await InteractionManager.drag(
            fromX: Double(fromX), fromY: Double(fromY),
            toX: Double(toX), toY: Double(toY),
            pressHoldMs: Double(InteractionManager.clampHoldMs(holdMs)),
            steps: steps.map { max(1, $0) },
            durationMs: UInt32(max(0, durationMs))
        )

        let result = DragResult(fromX: fromX, fromY: fromY, toX: toX, toY: toY)
        try emit(result, as: format) {
            print("Dragged (\(fromX), \(fromY)) → (\(toX), \(toY))")
        }
    }
}

import ArgumentParser
import Foundation

struct ScrollCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll",
        abstract: "Scroll at screen coordinates"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .long, help: "X screen coordinate")
    var x: Int

    @Option(name: .long, help: "Y screen coordinate")
    var y: Int

    @Option(name: .long, help: "Vertical scroll amount in pixels. Positive = scroll DOWN, negative = scroll UP")
    var deltaY: Int

    @Option(name: .long, help: "Horizontal scroll amount in pixels. Positive = scroll RIGHT, negative = scroll LEFT")
    var deltaX: Int = 0

    @Flag(name: .long, help: "Use drag gesture instead of scroll wheel (for touch-based apps like iOS Simulator)")
    var drag: Bool = false

    @Option(
        name: .long,
        help: "Spread the scroll across N phased events for smooth accel/decel motion (default 1 = instant jump)"
    )
    var steps: Int = 1

    @Option(
        name: .long,
        help: "Wall-clock duration in ms to spread a smooth scroll over (implies smooth; pairs with --steps)"
    )
    var durationMs: Int = 0

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    struct ScrollResult: Encodable {
        let x: Int
        let y: Int
        let deltaX: Int
        let deltaY: Int
    }

    func run() async throws {
        if let resolved = try await target.activateIfSpecified() {
            try await InteractionManager.ensureOnTarget(points: [(x, y)], pid: resolved.pid, windowID: target.windowID)
        }

        if drag {
            // Drag gesture: swipe from (x, y) to (x - deltaX, y - deltaY)
            // Negative because dragging up scrolls content down
            await InteractionManager.drag(
                fromX: Double(x), fromY: Double(y),
                toX: Double(x - deltaX), toY: Double(y - deltaY)
            )
        } else {
            await InteractionManager.scroll(
                x: Double(x), y: Double(y),
                deltaX: Int32(deltaX), deltaY: Int32(deltaY),
                steps: max(1, steps), durationMs: UInt32(max(0, durationMs))
            )
        }

        let result = ScrollResult(x: x, y: y, deltaX: deltaX, deltaY: deltaY)
        try emit(result, as: format) {
            print("Scrolled at (\(x), \(y)) by dx=\(deltaX), dy=\(deltaY)")
        }
    }
}

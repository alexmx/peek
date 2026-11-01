import ArgumentParser
import Foundation

struct ScrollCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll",
        abstract: "Scroll at screen coordinates"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .long, parsing: .unconditional, help: "X screen coordinate")
    var x: Int

    @Option(name: .long, parsing: .unconditional, help: "Y screen coordinate")
    var y: Int

    @Option(
        name: .long,
        parsing: .unconditional,
        help: "Vertical scroll amount in points. Positive = scroll DOWN, negative = scroll UP (drag mode: see --drag)"
    )
    var deltaY: Int

    @Option(
        name: .long,
        parsing: .unconditional,
        help: "Horizontal scroll amount in points. Positive = scroll RIGHT, negative = scroll LEFT"
    )
    var deltaX: Int = 0

    @Flag(
        name: .long,
        inversion: .prefixedNo,
        help: """
        --drag swipes like a finger instead of using the scroll wheel; --no-drag forces the wheel. \
        Default: drag over Xcode Device Hub / Simulator windows (they ignore wheel scrolls), wheel elsewhere. \
        A swipe's delta is finger travel in Mac screen points; the device is drawn scaled down, so its \
        content moves about delta / scale, minus a few points of touch slop.
        """
    )
    var drag: Bool?

    @Option(
        name: .long,
        help: "Spread the scroll across N events for smooth accel/decel motion (wheel default 1 = instant jump; swipes are always paced)"
    )
    var steps: Int = 1

    @Option(
        name: .long,
        help: "Wall-clock duration in ms of the scroll (wheel: implies smooth; swipe default 300-1000). Pairs with --steps"
    )
    var durationMs: Int = 0

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func run() async throws {
        try await target.activateAndGuard([(x, y)])

        let mode: InteractionManager.ScrollMode = drag.map { $0 ? .drag : .wheel }
            ?? InteractionManager.defaultScrollMode(x: x, y: y)
        await InteractionManager.scroll(
            x: x, y: y,
            deltaX: Int32(clamping: deltaX), deltaY: Int32(clamping: deltaY),
            mode: mode,
            steps: max(1, steps), durationMs: UInt32(max(0, durationMs))
        )

        let result = ScrollResult(x: x, y: y, deltaX: deltaX, deltaY: deltaY, mode: mode)
        try emit(result, as: format) {
            print("Scrolled at (\(x), \(y)) by dx=\(deltaX), dy=\(deltaY) (\(mode.rawValue))")
        }
    }
}

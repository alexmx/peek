import ArgumentParser
import CoreGraphics
import Foundation

struct MoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move",
        abstract: "Move the cursor (no click) — drives hover state, tooltips, cursor updates"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .long, help: "Destination X screen coordinate")
    var x: Int

    @Option(name: .long, help: "Destination Y screen coordinate")
    var y: Int

    @Option(name: .long, help: "Optional start X for smoothed motion (requires --from-y and --steps > 1)")
    var fromX: Int?

    @Option(name: .long, help: "Optional start Y for smoothed motion (requires --from-x and --steps > 1)")
    var fromY: Int?

    @Option(
        name: .long,
        help: "Number of intermediate moves between --from-* and --x/--y (default 1 = single jump). Only used when --from-x/--from-y are set."
    )
    var steps: Int = 1

    @Option(
        name: .long,
        help: "Milliseconds to sleep after the final move so hover state can settle / be captured. Default 0."
    )
    var dwellMs: Int = 0

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    struct CursorPoint: Encodable {
        let x: Int
        let y: Int
    }

    struct MoveResult: Encodable {
        let x: Int
        let y: Int
        let fromX: Int?
        let fromY: Int?
        let steps: Int
        let dwellMs: Int
        let cursor: CursorPoint?
        let element: AXNode?
    }

    func run() async throws {
        if target.windowID != nil || target.app != nil || target.pid != nil {
            let resolved = try await target.resolve()
            _ = try await InteractionManager.activate(pid: resolved.pid, windowID: resolved.windowID)
        }

        let clampedSteps = max(1, steps)
        let clampedDwell = max(0, dwellMs)

        InteractionManager.move(
            fromX: fromX.map(Double.init),
            fromY: fromY.map(Double.init),
            toX: Double(x),
            toY: Double(y),
            steps: clampedSteps,
            dwellMs: UInt32(clampedDwell)
        )

        // Readbacks: OS-reported cursor position (verifies the synthetic event actually
        // landed at the window-server level) + the topmost AX element under that point
        // (verifies the caller is hovering what they intended).
        let cursorLoc = CGEvent(source: nil)?.location
        let cursor = cursorLoc.map { CursorPoint(x: Int($0.x.rounded()), y: Int($0.y.rounded())) }
        let element: AXNode? = if let cursorLoc {
            try? AccessibilityManager.elementAtScreenPoint(x: cursorLoc.x, y: cursorLoc.y)
        } else {
            nil
        }

        let result = MoveResult(
            x: x,
            y: y,
            fromX: fromX,
            fromY: fromY,
            steps: clampedSteps,
            dwellMs: clampedDwell,
            cursor: cursor,
            element: element
        )
        switch format {
        case .json:
            try printJSON(result)
        case .toon:
            try printTOON(result)
        case .default:
            let cursorStr = cursor.map { " (cursor at \($0.x), \($0.y))" } ?? ""
            let elementStr = element.map { " over \($0.role)\($0.title.map { " \"\($0)\"" } ?? "")" } ?? ""
            if let fx = fromX, let fy = fromY, clampedSteps > 1 {
                print(
                    "Moved from (\(fx), \(fy)) to (\(x), \(y)) in \(clampedSteps) steps, dwell \(clampedDwell)ms\(cursorStr)\(elementStr)"
                )
            } else {
                print("Moved to (\(x), \(y)), dwell \(clampedDwell)ms\(cursorStr)\(elementStr)")
            }
        }
    }
}

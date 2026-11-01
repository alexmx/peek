import ArgumentParser
import CoreGraphics
import Foundation

struct ClickCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click at screen coordinates"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .long, parsing: .unconditional, help: "X screen coordinate")
    var x: Int

    @Option(name: .long, parsing: .unconditional, help: "Y screen coordinate")
    var y: Int

    @Option(
        name: .long,
        help: "Click count: 1 (single), 2 (double — selects word in text views), 3 (triple — selects line). Default 1."
    )
    var count: Int = 1

    @Option(
        name: .long,
        help: "Mouse button: left (default) or right. Right-click opens context menus on canvases / web views."
    )
    var button: String = "left"

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "Modifier keys held during the click: cmd, shift, option (alt), control (ctrl), fn. Space- or comma-separated. E.g. shift-click for range select, cmd-click to toggle / open in background."
    )
    var modifiers: [String] = []

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func run() async throws {
        guard let btn = InteractionManager.MouseButton(rawValue: button.lowercased()) else {
            throw PeekError.invalidArgument(name: "button", value: button, valid: ["left", "right"])
        }

        let modTokens = KeyMapping.modifierTokens(modifiers)
        let flags = try KeyMapping.parseModifiers(modTokens)

        try await target.activateAndGuard([(x, y)])

        await InteractionManager.click(x: Double(x), y: Double(y), count: count, button: btn, flags: flags)

        let result = ClickResult(x: x, y: y, count: max(1, min(count, 3)), button: btn.rawValue, modifiers: modTokens)
        try emit(result, as: format) {
            let multiplier = ["single", "double", "triple"][result.count - 1]
            let buttonLabel = btn == .right ? "right-clicked" : "clicked"
            let modText = modTokens.isEmpty ? "" : " with " + modTokens.joined(separator: "+")
            print("\(multiplier.capitalized) \(buttonLabel) at (\(x), \(y))\(modText)")
        }
    }
}

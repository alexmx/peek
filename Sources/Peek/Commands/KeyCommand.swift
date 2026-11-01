import ArgumentParser
import CoreGraphics
import Foundation

struct KeyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "key",
        abstract: "Send a single key chord (with optional modifiers) via keyboard events"
    )

    @OptionGroup var target: WindowTarget

    @Option(
        name: .long,
        help: "Key name: a single character (e.g. '1', 'a', '/') or a named key (escape, tab, return, delete, up, down, left, right, home, end, pageup, pagedown, f1-f12, space)"
    )
    var key: String

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "Modifier keys: cmd, shift, option (alt), control (ctrl), fn. Space- or comma-separated."
    )
    var modifiers: [String] = []

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func run() async throws {
        let tokens = KeyMapping.modifierTokens(modifiers)
        let flags = try KeyMapping.parseModifiers(tokens)

        guard let code = KeyMapping.keyCode(named: key) else {
            throw PeekError.invalidArgument(name: "key", value: key, valid: KeyMapping.allKeyNames)
        }

        try await target.activate(strict: false)

        await InteractionManager.sendKey(keyCode: code, flags: flags)

        let result = KeyResult(key: key, modifiers: tokens, keyCode: Int(code))

        try emit(result, as: format) {
            let modText = tokens.isEmpty ? "" : tokens.joined(separator: "+") + "+"
            print("Sent \(modText)\(key) (keyCode \(code))")
        }
    }
}

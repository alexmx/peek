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

    struct KeyResult: Encodable {
        let key: String
        let modifiers: [String]
        let keyCode: Int
    }

    func run() async throws {
        let tokens = modifiers
            .flatMap { $0.split(separator: ",").map(String.init) }
            .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let flags = try KeyMapping.parseModifiers(tokens)

        guard let code = KeyMapping.keyCode(named: key) else {
            throw PeekError.invalidArgument(name: "key", value: key, valid: KeyMapping.allKeyNames)
        }

        if target.windowID != nil || target.app != nil || target.pid != nil {
            let resolved = try await target.resolve()
            _ = try await InteractionManager.activate(pid: resolved.pid, windowID: resolved.windowID)
        }

        InteractionManager.sendKey(keyCode: code, flags: flags)

        let result = KeyResult(key: key, modifiers: tokens, keyCode: Int(code))

        switch format {
        case .json:
            try printJSON(result)
        case .toon:
            try printTOON(result)
        case .default:
            let modText = tokens.isEmpty ? "" : tokens.joined(separator: "+") + "+"
            print("Sent \(modText)\(key) (keyCode \(code))")
        }
    }
}

import ArgumentParser
import Foundation

struct TextCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Read full text content from an element, including parameterized (NavigableStaticText) text"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .long, help: "Filter by role (e.g. StaticText, TextArea)")
    var role: String?

    @Option(name: .long, help: "Filter by title (case-insensitive substring)")
    var title: String?

    @Option(name: .long, help: "Filter by value (case-insensitive substring)")
    var value: String?

    @Option(name: .long, help: "Filter by description (case-insensitive substring)")
    var desc: String?

    @Option(name: .long, help: "Start character offset (default 0)")
    var offset: Int = 0

    @Option(
        name: .long,
        help: "Max characters to read (default \(AccessibilityManager.textReadCap); pages with --offset)"
    )
    var length: Int?

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func validate() throws {
        if role == nil, title == nil, value == nil, desc == nil {
            throw ValidationError("Provide at least one filter: --role, --title, --value, or --desc")
        }
    }

    func run() async throws {
        let resolved = try await target.resolve()
        let result = try AccessibilityManager.readText(
            pid: resolved.pid,
            windowID: resolved.windowID,
            role: role,
            title: title,
            value: value,
            description: desc,
            offset: offset,
            length: length
        )

        switch format {
        case .json:
            try printJSON(result)
        case .toon:
            try printTOON(result)
        case .default:
            print(result.text)
            if result.truncated {
                let next = result.offset + result.text.count
                print("\n[\(next)/\(result.length) chars; read more with --offset \(next)]")
            }
        }
    }
}

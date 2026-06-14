import ArgumentParser
import Foundation

struct LaunchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch a macOS application by bundle ID, name, or path"
    )

    @Option(name: .long, help: "Bundle identifier (e.g. com.apple.calculator)")
    var bundleID: String?

    @Option(
        name: .long,
        help: "App display name (searches /Applications, /System/Applications, /System/Applications/Utilities)"
    )
    var name: String?

    @Option(name: .long, help: "Absolute path to a .app bundle")
    var path: String?

    @Flag(name: .long, help: "Wait until at least one AX-visible window appears (timeout: 10s)")
    var waitForWindow: Bool = false

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func run() async throws {
        let url = try AppLifecycleManager.resolveAppURL(bundleID: bundleID, name: name, path: path)
        let result = try await AppLifecycleManager.launch(url: url, waitForWindow: waitForWindow)
        switch format {
        case .json: try printJSON(result)
        case .toon: try printTOON(result)
        case .default:
            print("Launched \(result.name) (pid \(result.pid), bundle \(result.bundleID ?? "?"))")
        }
    }
}

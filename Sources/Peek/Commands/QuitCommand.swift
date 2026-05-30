import ArgumentParser
import Foundation

struct QuitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quit",
        abstract: "Terminate a running application gracefully (or forcibly with --force)"
    )

    @Option(name: .long, help: "Process ID")
    var pid: Int32?

    @Option(name: .long, help: "Bundle identifier (e.g. com.apple.calculator)")
    var bundleID: String?

    @Option(name: .long, help: "App display name (case-insensitive substring)")
    var name: String?

    @Flag(name: .long, help: "Force-terminate with forceTerminate() instead of graceful terminate()")
    var force: Bool = false

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func run() async throws {
        let result = try AppLifecycleManager.quit(pid: pid, bundleID: bundleID, name: name, force: force)
        switch format {
        case .json: try printJSON(result)
        case .toon: try printTOON(result)
        case .default:
            print("\(force ? "Force-quit" : "Quit") \(result.name) (pid \(result.pid))")
        }
    }
}

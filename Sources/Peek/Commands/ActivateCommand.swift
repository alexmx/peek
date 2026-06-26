import ArgumentParser
import Foundation

struct ActivateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activate",
        abstract: "Bring an app to the foreground and raise its window"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func run() async throws {
        let resolved = try await target.resolve()

        let result = try await InteractionManager.activate(pid: resolved.pid, windowID: resolved.windowID)

        try emit(result, as: format) {
            print("Activated \(result.app) (pid \(result.pid), window \(result.windowID))")
        }
    }
}

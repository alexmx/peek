import ArgumentParser
import Foundation

struct ActivateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activate",
        abstract: "Bring an app to the foreground and raise its window"
    )

    @OptionGroup var target: WindowTarget

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func run() throws {
        let windowID = try target.resolve()
        guard let pid = WindowManager.pid(forWindowID: windowID) else {
            throw PeekError.windowNotFound(windowID)
        }

        let result = try InteractionManager.activate(pid: pid, windowID: windowID)

        if format == .json {
            try printJSON(result)
        } else {
            print("Activated \(result.app) (pid \(result.pid), window \(result.windowID))")
        }
    }
}

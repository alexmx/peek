import ArgumentParser
import Foundation

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check permissions and system readiness"
    )

    @Flag(name: .long, help: "Prompt for missing permissions via System Settings")
    var prompt: Bool = false

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func run() throws {
        let status = PermissionManager.checkAll(prompt: prompt)

        switch format {
        case .json:
            try printJSON(status)
        case .toon:
            try printTOON(status)
        case .default:
            print("Accessibility:    \(status.accessibility ? "granted" : "not granted")")
            print("Screen Recording: \(status.screenRecording ? "granted" : "not granted")")

            if status.accessibility, status.screenRecording {
                print("\nAll permissions granted. peek is ready to use.")
                print("Run 'peek doctor --prompt' to re-request permissions if needed.")
            } else if prompt {
                print("\nOpening System Settings for missing permissions...")
            } else {
                print("\nRun 'peek doctor --prompt' to request missing permissions.")
            }
        }
    }
}

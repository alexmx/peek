import ArgumentParser

@main
struct Peek: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "macOS Window Inspector",
        subcommands: [
            // Discovery
            AppsCommand.self,
            // Inspection
            WindowCommand.self,
            FindCommand.self,
            TextCommand.self,
            MenuCommand.self,
            // Interaction
            ClickCommand.self,
            MoveCommand.self,
            ScrollCommand.self,
            DragCommand.self,
            TypeCommand.self,
            KeyCommand.self,
            ActionCommand.self,
            ActivateCommand.self,
            LaunchCommand.self,
            QuitCommand.self,
            // Monitoring
            CaptureCommand.self,
            // System
            DoctorCommand.self,
            MCPServerCommand.self
        ]
    )

    @Flag(name: .shortAndLong, help: "Show version")
    var version = false

    mutating func run() throws {
        if version {
            print(peekVersion)
        } else {
            throw CleanExit.helpRequest(self)
        }
    }
}

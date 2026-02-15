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
            MenuCommand.self,
            // Interaction
            ClickCommand.self,
            TypeCommand.self,
            ActionCommand.self,
            ActivateCommand.self,
            // Monitoring
            WatchCommand.self,
            CaptureCommand.self,
            // System
            DoctorCommand.self,
            MCPServerCommand.self
        ]
    )
}

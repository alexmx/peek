import ArgumentParser

@main
struct Peek: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "macOS Window Inspector",
        subcommands: [
            ListCommand.self,
            CaptureCommand.self,
            InspectCommand.self,
            FindCommand.self,
            ElementAtCommand.self,
            ClickCommand.self,
            TypeCommand.self,
            ActionCommand.self,
            WatchCommand.self,
            DiffCommand.self,
            AppsCommand.self,
            MenuCommand.self,
        ]
    )
}

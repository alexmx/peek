import ArgumentParser
import CoreGraphics
import Foundation

struct AppsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apps",
        abstract: "List running applications and their windows"
    )

    @Option(name: .long, help: "Filter by app name (case-insensitive substring)")
    var app: String?

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func run() async throws {
        let windows = try await WindowManager.listWindows()
        var apps = AppManager.listApps(windows: windows)

        if let app {
            apps = apps.filter { $0.name.localizedCaseInsensitiveContains(app) }
        }

        switch format {
        case .json:
            try printJSON(apps)
        case .toon:
            try printTOON(apps)
        case .default:
            printAppList(apps)
        }
    }

    private func printAppList(_ apps: [AppEntry]) {
        if apps.isEmpty {
            print("No applications found.")
            return
        }

        for (index, app) in apps.enumerated() {
            var header = "\(app.name) (\(app.pid))"
            if let bundle = app.bundleID { header += "  \(bundle)" }
            if app.isActive { header += "  [active]" }
            if app.isHidden { header += "  [hidden]" }
            print(header)

            if app.windows.isEmpty {
                print("  (no windows)")
            } else {
                for w in app.windows {
                    let title = w.title.isEmpty ? "(untitled)" : w.title
                    let id = "\(w.windowID)".padding(toLength: 8, withPad: " ", startingAt: 0)
                    let ttl = String(title.prefix(30)).padding(toLength: 31, withPad: " ", startingAt: 0)
                    let frame = "(\(w.frame.x), \(w.frame.y)) \(w.frame.width)x\(w.frame.height)"
                    let onScreen = w.isOnScreen ? "" : "  [offscreen]"
                    print("  \(id)\(ttl)\(frame)\(onScreen)")
                }
            }

            if index < apps.count - 1 { print("") }
        }

        let windowCount = apps.reduce(0) { $0 + $1.windows.count }
        print("\n\(apps.count) app(s), \(windowCount) window(s).")
    }
}

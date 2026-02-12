import ArgumentParser
import Foundation

struct AppsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apps",
        abstract: "List running applications with bundle IDs and PIDs"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    func run() throws {
        let apps = AppInfo.listApps()
        if json {
            try printJSON(apps)
        } else {
            printAppList(apps)
        }
    }

    private func printAppList(_ apps: [AppEntry]) {
        if apps.isEmpty {
            print("No applications found.")
            return
        }

        let header = "PID".padding(toLength: 8, withPad: " ", startingAt: 0)
            + "App".padding(toLength: 26, withPad: " ", startingAt: 0)
            + "Bundle ID".padding(toLength: 40, withPad: " ", startingAt: 0)
            + "State"
        print(header)
        print(String(repeating: "-", count: 90))

        for app in apps {
            let pid = "\(app.pid)".padding(toLength: 8, withPad: " ", startingAt: 0)
            let name = String(app.name.prefix(25)).padding(toLength: 26, withPad: " ", startingAt: 0)
            let bundle = String((app.bundleID ?? "—").prefix(39)).padding(toLength: 40, withPad: " ", startingAt: 0)
            var state = ""
            if app.isActive { state += "[active]" }
            if app.isHidden { state += "[hidden]" }
            print("\(pid)\(name)\(bundle)\(state)")
        }

        print("\n\(apps.count) application(s) found.")
    }
}

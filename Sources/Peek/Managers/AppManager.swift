import AppKit
import CoreGraphics
import Foundation

enum AppManager {
    /// A running app's details, copied on the main actor so they can be used from any thread
    /// (see `runningApps`).
    struct RunningApp: Sendable {
        let pid: pid_t
        let name: String?
        let bundleID: String?
        /// A regular (Dock) app rather than an agent or background process.
        let isRegular: Bool
        var isActive = false
        var isHidden = false
    }

    /// The running apps, read on the main actor. NSWorkspace's list and each
    /// NSRunningApplication's changing properties (activation policy, active, hidden) only
    /// refresh on the main thread. Read from a background thread, where MCP tools run, a
    /// long-running process keeps what it saw first: the MCP server never saw an app launched
    /// after its first query.
    @MainActor
    static func runningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications.map {
            RunningApp(
                pid: $0.processIdentifier,
                name: $0.localizedName,
                bundleID: $0.bundleIdentifier,
                isRegular: $0.activationPolicy == .regular,
                isActive: $0.isActive,
                isHidden: $0.isHidden
            )
        }
    }

    /// The running app that best matches `query` (see `bestMatch`). `regularOnly` limits the
    /// search to regular (Dock-visible) apps — used by `quit`, so a name can't hit system agents.
    static func runningApp(named query: String, regularOnly: Bool = false) async -> RunningApp? {
        let apps = await runningApps()
        return bestMatch(query, in: regularOnly ? apps.filter(\.isRegular) : apps)
    }

    /// Rank apps against a case-insensitive name query: exact name, then name substring
    /// (regular apps before background ones), then bundle-ID substring. Within a rank,
    /// the first app in `apps` wins.
    static func bestMatch(_ query: String, in apps: [RunningApp]) -> RunningApp? {
        func nameContains(_ app: RunningApp) -> Bool {
            app.name?.localizedCaseInsensitiveContains(query) == true
        }
        return apps.first { $0.name?.localizedCaseInsensitiveCompare(query) == .orderedSame }
            ?? apps.first { $0.isRegular && nameContains($0) }
            ?? apps.first(where: nameContains)
            ?? apps.first { $0.bundleID?.localizedCaseInsensitiveContains(query) == true }
    }

    /// The regular apps among `apps`, each with its windows from `windows`, sorted by name.
    /// `includeWindowOwners` also lists non-regular (accessory/LSUIElement) apps that own at
    /// least one window in `windows` — menu-bar apps are accessory-policy, so a panels listing
    /// would otherwise drop exactly the apps it exists to surface.
    static func listApps(
        _ apps: [RunningApp],
        windows: [WindowInfo],
        includeWindowOwners: Bool = false
    ) -> [AppEntry] {
        let windowsByPID = Dictionary(grouping: windows, by: { $0.pid })

        return apps
            .filter { $0.isRegular || (includeWindowOwners && windowsByPID[$0.pid] != nil) }
            .map { app in
                let appWindows = (windowsByPID[app.pid] ?? []).map { w in
                    AppEntry.WindowEntry(
                        windowID: w.windowID,
                        title: w.windowTitle,
                        frame: AXNode.FrameInfo(w.frame),
                        isOnScreen: w.isOnScreen,
                        layer: w.layer
                    )
                }
                return AppEntry(
                    name: app.name ?? "unknown",
                    bundleID: app.bundleID,
                    pid: app.pid,
                    isActive: app.isActive,
                    isHidden: app.isHidden,
                    windows: appWindows
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

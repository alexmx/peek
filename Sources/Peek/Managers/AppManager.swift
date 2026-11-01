import AppKit
import CoreGraphics
import Foundation

enum AppManager {
    /// The running-app fields `bestMatch` ranks on, decoupled from NSRunningApplication for tests.
    struct AppCandidate {
        let pid: pid_t
        let name: String?
        let bundleID: String?
        let isRegular: Bool
    }

    /// The running app that best matches `query` (see `bestMatch`). `regularOnly` limits the
    /// search to regular (Dock-visible) apps — used by `quit`, so a name can't hit system agents.
    static func runningApp(named query: String, regularOnly: Bool = false) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
            .filter { !regularOnly || $0.activationPolicy == .regular }
        let candidates = apps.map {
            AppCandidate(
                pid: $0.processIdentifier,
                name: $0.localizedName,
                bundleID: $0.bundleIdentifier,
                isRegular: $0.activationPolicy == .regular
            )
        }
        guard let match = bestMatch(query, in: candidates) else { return nil }
        return apps.first { $0.processIdentifier == match.pid }
    }

    /// Rank apps against a case-insensitive name query: exact name, then name substring
    /// (regular apps before background ones), then bundle-ID substring. Within a rank,
    /// the first app in `apps` wins.
    static func bestMatch(_ query: String, in apps: [AppCandidate]) -> AppCandidate? {
        func nameContains(_ app: AppCandidate) -> Bool {
            app.name?.localizedCaseInsensitiveContains(query) == true
        }
        return apps.first { $0.name?.localizedCaseInsensitiveCompare(query) == .orderedSame }
            ?? apps.first { $0.isRegular && nameContains($0) }
            ?? apps.first(where: nameContains)
            ?? apps.first { $0.bundleID?.localizedCaseInsensitiveContains(query) == true }
    }

    /// `includeWindowOwners` also lists non-regular (accessory/LSUIElement) apps that own
    /// at least one window in `windows` — menu-bar apps are accessory-policy, so a panels
    /// listing would otherwise drop exactly the apps it exists to surface.
    static func listApps(windows: [WindowInfo], includeWindowOwners: Bool = false) -> [AppEntry] {
        let windowsByPID = Dictionary(grouping: windows, by: { $0.pid })

        return NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular
                    || (includeWindowOwners && windowsByPID[$0.processIdentifier] != nil)
            }
            .map { app in
                let pid = app.processIdentifier
                let appWindows = (windowsByPID[pid] ?? []).map { w in
                    AppEntry.WindowEntry(
                        windowID: w.windowID,
                        title: w.windowTitle,
                        frame: AXNode.FrameInfo(w.frame),
                        isOnScreen: w.isOnScreen,
                        layer: w.layer
                    )
                }
                return AppEntry(
                    name: app.localizedName ?? "unknown",
                    bundleID: app.bundleIdentifier,
                    pid: pid,
                    isActive: app.isActive,
                    isHidden: app.isHidden,
                    windows: appWindows
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

import AppKit
import CoreGraphics
import Foundation

enum AppManager {
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
                        frame: AXNode.FrameInfo(
                            x: Int(w.frame.origin.x),
                            y: Int(w.frame.origin.y),
                            width: Int(w.frame.width),
                            height: Int(w.frame.height)
                        ),
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

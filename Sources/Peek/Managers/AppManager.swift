import AppKit
import CoreGraphics
import Foundation

enum AppManager {
    static func listApps(windows: [WindowInfo]) -> [AppEntry] {
        let windowsByPID = Dictionary(grouping: windows, by: { $0.pid })

        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
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
                        isOnScreen: w.isOnScreen
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

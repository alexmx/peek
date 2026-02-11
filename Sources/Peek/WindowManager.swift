import CoreGraphics
import Foundation
import ScreenCaptureKit

struct WindowInfo: Sendable {
    let windowID: CGWindowID
    let ownerName: String
    let windowTitle: String
    let pid: pid_t
    let frame: CGRect
    let isOnScreen: Bool
}

enum WindowManager {
    /// Uses ScreenCaptureKit to list real windows across all desktops.
    static func listWindows() async throws -> [WindowInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: false
        )

        let onScreenIDs = onScreenWindowIDs()

        return content.windows.compactMap { scWindow in
            guard let app = scWindow.owningApplication,
                  scWindow.windowLayer == 0 else { return nil }

            let frame = scWindow.frame
            guard frame.width > 200, frame.height > 200 else { return nil }

            let title = scWindow.title ?? ""
            let isOnScreen = onScreenIDs.contains(scWindow.windowID)

            // Offscreen + no title = placeholder/staging window
            if !isOnScreen && title.isEmpty { return nil }

            // Skip AutoFill helper windows
            if app.applicationName.hasPrefix("AutoFill") { return nil }

            return WindowInfo(
                windowID: scWindow.windowID,
                ownerName: app.applicationName,
                windowTitle: title,
                pid: app.processID,
                frame: frame,
                isOnScreen: isOnScreen
            )
        }
    }

    /// Lightweight PID lookup for a window ID using CGWindowList (no permissions needed).
    static func pid(forWindowID windowID: CGWindowID) -> pid_t? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for entry in list {
            if let id = entry[kCGWindowNumber as String] as? CGWindowID,
               id == windowID,
               let pid = entry[kCGWindowOwnerPID as String] as? pid_t {
                return pid
            }
        }
        return nil
    }

    static func printWindowList(_ windows: [WindowInfo]) {
        if windows.isEmpty {
            print("No windows found.")
            return
        }

        let header = "ID".padding(toLength: 8, withPad: " ", startingAt: 0)
            + "PID".padding(toLength: 8, withPad: " ", startingAt: 0)
            + "App".padding(toLength: 26, withPad: " ", startingAt: 0)
            + "Title".padding(toLength: 31, withPad: " ", startingAt: 0)
            + "Frame"
        print(header)
        print(String(repeating: "-", count: 110))

        for w in windows {
            let title = w.windowTitle.isEmpty ? "(untitled)" : w.windowTitle
            let app = String(w.ownerName.prefix(25)).padding(toLength: 26, withPad: " ", startingAt: 0)
            let ttl = String(title.prefix(30)).padding(toLength: 31, withPad: " ", startingAt: 0)
            let id = "\(w.windowID)".padding(toLength: 8, withPad: " ", startingAt: 0)
            let pid = "\(w.pid)".padding(toLength: 8, withPad: " ", startingAt: 0)
            let frameStr = "(\(Int(w.frame.origin.x)), \(Int(w.frame.origin.y))) \(Int(w.frame.width))x\(Int(w.frame.height))"
            let onScreen = w.isOnScreen ? "" : " [offscreen]"

            print("\(id)\(pid)\(app)\(ttl)\(frameStr)\(onScreen)")
        }

        print("\n\(windows.count) window(s) found.")
    }

    private static func onScreenWindowIDs() -> Set<CGWindowID> {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var ids = Set<CGWindowID>()
        for entry in list {
            if let id = entry[kCGWindowNumber as String] as? CGWindowID {
                ids.insert(id)
            }
        }
        return ids
    }
}

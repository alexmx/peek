import CoreGraphics
import Foundation
import ScreenCaptureKit

enum WindowManager {
    private static let minWindowSize: CGFloat = 200

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
            guard frame.width > minWindowSize, frame.height > minWindowSize else { return nil }

            let title = scWindow.title ?? ""
            let isOnScreen = onScreenIDs.contains(scWindow.windowID)

            // Offscreen + no title = placeholder/staging window
            if !isOnScreen, title.isEmpty { return nil }

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

    /// Find the first window ID for an app by name (case-insensitive substring match).
    static func windowID(forApp name: String) -> CGWindowID? {
        let entries = windowListEntries()
        let onScreen = onScreenWindowIDs()

        // Prefer on-screen windows, fall back to any matching window.
        var fallback: CGWindowID?

        for entry in entries {
            guard let ownerName = entry[kCGWindowOwnerName as String] as? String,
                  ownerName.localizedCaseInsensitiveContains(name),
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  isRealWindow(entry)
            else { continue }

            if onScreen.contains(id) {
                return id
            }
            if fallback == nil {
                fallback = id
            }
        }
        return fallback
    }

    /// Find the first window ID for a given PID.
    static func windowID(forPID pid: pid_t) -> CGWindowID? {
        let entries = windowListEntries()
        let onScreen = onScreenWindowIDs()

        var fallback: CGWindowID?

        for entry in entries {
            guard let entryPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  entryPID == pid,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  isRealWindow(entry)
            else { continue }

            if onScreen.contains(id) {
                return id
            }
            if fallback == nil {
                fallback = id
            }
        }
        return fallback
    }

    /// Lightweight PID lookup for a window ID using CGWindowList (no permissions needed).
    static func pid(forWindowID windowID: CGWindowID) -> pid_t? {
        for entry in windowListEntries() {
            if let id = entry[kCGWindowNumber as String] as? CGWindowID,
               id == windowID,
               let pid = entry[kCGWindowOwnerPID as String] as? pid_t
            {
                return pid
            }
        }
        return nil
    }

    // MARK: - Private

    private static func windowListEntries() -> [[String: Any]] {
        CGWindowListCopyWindowInfo(
            [.optionAll],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
    }

    /// Checks layer == 0 and minimum size to skip helper/overlay windows.
    private static func isRealWindow(_ entry: [String: Any]) -> Bool {
        guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else {
            return false
        }
        guard let bounds = entry[kCGWindowBounds as String] as? [String: Any],
              let width = bounds["Width"] as? CGFloat,
              let height = bounds["Height"] as? CGFloat,
              width > minWindowSize, height > minWindowSize
        else {
            return false
        }
        return true
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

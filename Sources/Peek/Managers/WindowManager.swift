import CoreGraphics
import Foundation
import ScreenCaptureKit

enum WindowManager {
    private static let minWindowSize: CGFloat = 200

    /// Fetch all real windows using ScreenCaptureKit.
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

    /// Get the bounds (in points) of a window by ID.
    static func windowBounds(forWindowID windowID: CGWindowID) async throws -> CGSize? {
        let windows = try await listWindows()
        return windows.first { $0.windowID == windowID }.map {
            CGSize(width: $0.frame.width, height: $0.frame.height)
        }
    }

    // MARK: - Private

    /// On-screen window IDs via CGWindowList (lightweight, no permissions needed).
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

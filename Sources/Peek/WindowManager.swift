import CoreGraphics
import Foundation
import ScreenCaptureKit

struct WindowInfo: Sendable, Encodable {
    let windowID: CGWindowID
    let ownerName: String
    let windowTitle: String
    let pid: pid_t
    let frame: CGRect
    let isOnScreen: Bool

    enum CodingKeys: String, CodingKey {
        case windowID, ownerName, windowTitle, pid, frame, isOnScreen
    }

    struct FrameJSON: Encodable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(windowID, forKey: .windowID)
        try container.encode(ownerName, forKey: .ownerName)
        try container.encode(windowTitle, forKey: .windowTitle)
        try container.encode(pid, forKey: .pid)
        try container.encode(FrameJSON(
            x: Int(frame.origin.x),
            y: Int(frame.origin.y),
            width: Int(frame.width),
            height: Int(frame.height)
        ), forKey: .frame)
        try container.encode(isOnScreen, forKey: .isOnScreen)
    }
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
               let pid = entry[kCGWindowOwnerPID as String] as? pid_t
            {
                return pid
            }
        }
        return nil
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

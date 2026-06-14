import CoreGraphics
import Foundation
import ScreenCaptureKit

enum WindowManager {
    private static let minWindowSize: CGFloat = 200

    private static let cacheTTL: TimeInterval = 0.3
    nonisolated(unsafe) private static var cache: (windows: [WindowInfo], timestamp: Date)?
    private static let cacheLock = NSLock()

    private static func cachedSnapshot() -> [WindowInfo]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache, Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.windows
        }
        return nil
    }

    private static func storeSnapshot(_ windows: [WindowInfo]) {
        cacheLock.lock()
        cache = (windows, Date())
        cacheLock.unlock()
    }

    static func invalidateCache() {
        cacheLock.lock()
        cache = nil
        cacheLock.unlock()
    }

    static func listWindows() async throws -> [WindowInfo] {
        if let cached = cachedSnapshot() { return cached }

        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: false
        )

        let onScreenIDs = onScreenWindowIDs()

        let result = content.windows.compactMap { scWindow -> WindowInfo? in
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

        storeSnapshot(result)
        return result
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

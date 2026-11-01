import CoreGraphics
import Foundation
import Synchronization

enum WindowManager {
    private static let minWindowSize: CGFloat = 200

    private static let cacheTTL: TimeInterval = 0.3
    private static let cache = Mutex<(windows: [WindowInfo], timestamp: Date)?>(nil)

    private static func cachedSnapshot() -> [WindowInfo]? {
        cache.withLock { cached in
            if let cached, Date().timeIntervalSince(cached.timestamp) < cacheTTL {
                return cached.windows
            }
            return nil
        }
    }

    private static func storeSnapshot(_ windows: [WindowInfo]) {
        cache.withLock { $0 = (windows, Date()) }
    }

    static func invalidateCache() {
        cache.withLock { $0 = nil }
    }

    /// `includePanels` keeps windows the default listing filters out — menu-bar panels
    /// (MenuBarExtra), status items, small utility windows — and skips the cache (the
    /// snapshot only ever holds the filtered listing).
    static func listWindows(includePanels: Bool = false) async throws -> [WindowInfo] {
        if !includePanels, let cached = cachedSnapshot() { return cached }

        // CGWindowList itself needs no permission, but window *titles* (kCGWindowName) only
        // populate with Screen Recording granted — gate so callers get an actionable permission
        // error instead of untitled windows they can't target by name.
        guard CGPreflightScreenCaptureAccess() else {
            throw PeekError.screenCaptureNotGranted
        }

        let result = cgWindowList(includePanels: includePanels)
        if !includePanels { storeSnapshot(result) }
        return result
    }

    /// Direct single-window lookup — sees windows the filtered listing drops (menu-bar
    /// panels, status items, small utility windows). Backs the explicit-window-ID fallback
    /// in `WindowTarget.resolve`. Scans the full `.optionAll` list rather than using
    /// `.optionIncludingWindow`: relative queries return nothing for off-screen windows,
    /// and a dismissed MenuBarExtra panel is exactly that (off-screen, backing store intact).
    static func windowInfo(byID windowID: CGWindowID) -> WindowInfo? {
        guard windowID != kCGNullWindowID,
              let record = windowRecords([.optionAll]).first(where: { $0.windowID == windowID })
        else { return nil }
        return WindowInfo(
            windowID: windowID,
            ownerName: record.ownerName,
            windowTitle: record.title,
            pid: record.pid,
            frame: record.bounds,
            isOnScreen: record.isOnScreen ?? false,
            layer: record.layer
        )
    }

    /// Parsed `CGWindowListCopyWindowInfo` entries, in the order CG returns them
    /// (front-to-back for on-screen queries). Malformed entries are skipped.
    static func windowRecords(_ options: CGWindowListOption) -> [WindowRecord] {
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap(WindowRecord.init)
    }

    /// On-screen window IDs in front-to-back z-order (frontmost first), via CGWindowList.
    /// Used to resolve `--app`/`--pid` to the frontmost matching window.
    static func onScreenWindowIDsFrontToBack() -> [CGWindowID] {
        windowRecords([.optionOnScreenOnly, .excludeDesktopElements]).map(\.windowID)
    }

    // MARK: - Private

    /// Enumerate user windows via `CGWindowListCopyWindowInfo` — synchronous and in-process.
    /// Unlike `SCShareableContent` it never round-trips to `replayd`, so it can't hang/wedge:
    /// the old ScreenCaptureKit enumeration hung ~49s (ignoring cancellation) and pinned
    /// `replayd`, the root of the "MCP dies after a while" reports. `.optionAll` includes
    /// off-screen/minimized windows; on-screen state comes from the lightweight on-screen list.
    private static func cgWindowList(includePanels: Bool = false) -> [WindowInfo] {
        let onScreenIDs = Set(windowRecords([.optionOnScreenOnly]).map(\.windowID))
        return windowRecords([.optionAll, .excludeDesktopElements]).compactMap { record -> WindowInfo? in
            if !includePanels {
                // Normal-layer windows only — drop menu bar, Dock, status items, panels,
                // and tiny utility windows.
                guard record.layer == 0,
                      record.bounds.width > minWindowSize,
                      record.bounds.height > minWindowSize
                else { return nil }
            }

            // AutoFill helper windows masquerade as their host app; drop them.
            if record.ownerName.hasPrefix("AutoFill") { return nil }

            let isOnScreen = onScreenIDs.contains(record.windowID)
            // Off-screen with no title = placeholder/staging window. Panels are exempt:
            // a dismissed MenuBarExtra panel is off-screen and untitled, yet its backing
            // store persists and stays capturable by window ID.
            if !includePanels, !isOnScreen, record.title.isEmpty { return nil }

            return WindowInfo(
                windowID: record.windowID,
                ownerName: record.ownerName,
                windowTitle: record.title,
                pid: record.pid,
                frame: record.bounds,
                isOnScreen: isOnScreen,
                layer: record.layer
            )
        }
    }
}

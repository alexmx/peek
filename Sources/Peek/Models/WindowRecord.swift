import CoreGraphics
import Foundation

/// One entry of `CGWindowListCopyWindowInfo`, parsed once (see `WindowManager.windowRecords`).
struct WindowRecord {
    let windowID: CGWindowID
    let pid: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect
    /// CGWindow layer: 0 = normal app window, 25 = status item, 101 = menu/panel.
    let layer: Int
    /// `kCGWindowIsOnscreen`. CGWindowList omits the key for off-screen windows, so nil
    /// usually means off-screen.
    let isOnScreen: Bool?
    let alpha: Double
}

extension WindowRecord {
    /// Parse a raw CGWindowList dictionary. Nil when the ID, owner PID or bounds are missing.
    init?(_ info: [String: Any]) {
        guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
        else { return nil }
        self.init(
            windowID: windowID,
            pid: pid,
            ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
            title: info[kCGWindowName as String] as? String ?? "",
            bounds: bounds,
            layer: info[kCGWindowLayer as String] as? Int ?? 0,
            isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool,
            alpha: info[kCGWindowAlpha as String] as? Double ?? 1.0
        )
    }
}

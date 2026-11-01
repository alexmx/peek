import CoreGraphics
import Foundation

struct WindowInfo {
    let windowID: CGWindowID
    let ownerName: String
    let windowTitle: String
    let pid: pid_t
    let frame: CGRect
    let isOnScreen: Bool
    /// CGWindow layer: 0 = normal app window, 25 = status item, 101 = menu/panel.
    let layer: Int

    init(
        windowID: CGWindowID,
        ownerName: String,
        windowTitle: String,
        pid: pid_t,
        frame: CGRect,
        isOnScreen: Bool,
        layer: Int = 0
    ) {
        self.windowID = windowID
        self.ownerName = ownerName
        self.windowTitle = windowTitle
        self.pid = pid
        self.frame = frame
        self.isOnScreen = isOnScreen
        self.layer = layer
    }
}

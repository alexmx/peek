import CoreGraphics
import Foundation

struct AppEntry: Encodable {
    let name: String
    let bundleID: String?
    let pid: pid_t
    let isActive: Bool
    let isHidden: Bool
    let windows: [WindowEntry]

    struct WindowEntry: Encodable {
        let windowID: CGWindowID
        let title: String
        let frame: AXNode.FrameInfo
        let isOnScreen: Bool
        /// CGWindow layer: 0 = normal app window, 25 = status item, 101 = menu/panel.
        let layer: Int
    }
}

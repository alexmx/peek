import CoreGraphics
import Foundation

struct WindowInfo: Encodable {
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

    enum CodingKeys: String, CodingKey {
        case windowID, ownerName, windowTitle, pid, frame, isOnScreen, layer
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(windowID, forKey: .windowID)
        try container.encode(ownerName, forKey: .ownerName)
        try container.encode(windowTitle, forKey: .windowTitle)
        try container.encode(pid, forKey: .pid)
        try container.encode(AXNode.FrameInfo(
            x: Int(frame.origin.x),
            y: Int(frame.origin.y),
            width: Int(frame.width),
            height: Int(frame.height)
        ), forKey: .frame)
        try container.encode(isOnScreen, forKey: .isOnScreen)
        try container.encode(layer, forKey: .layer)
    }
}

import CoreGraphics
import Foundation

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
    }
}

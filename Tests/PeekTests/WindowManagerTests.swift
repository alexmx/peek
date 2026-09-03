import CoreGraphics
import Foundation
@testable import peek
import Testing

@Suite("WindowManager Tests")
struct WindowManagerTests {
    // MARK: - windowInfo(byID:) Tests

    @Test
    func windowInfoByIDRejectsSentinel() {
        // Window ID 0 is the window-less-app sentinel (see WindowTarget.findWindow);
        // it must never resolve to a real window.
        #expect(WindowManager.windowInfo(byID: kCGNullWindowID) == nil)
    }

    @Test
    func windowInfoByIDNonexistent() {
        // CGWindowIDs are allocated from small values; the top of the range never exists.
        #expect(WindowManager.windowInfo(byID: CGWindowID.max) == nil)
    }

    // MARK: - WindowInfo Tests

    @Test
    func windowInfoLayerDefaultsToZero() {
        let info = WindowInfo(
            windowID: 1,
            ownerName: "App",
            windowTitle: "Window",
            pid: 100,
            frame: CGRect(x: 0, y: 0, width: 400, height: 300),
            isOnScreen: true
        )
        #expect(info.layer == 0)
    }

    @Test
    func windowInfoEncodesLayer() throws {
        let info = WindowInfo(
            windowID: 1,
            ownerName: "App",
            windowTitle: "Panel",
            pid: 100,
            frame: CGRect(x: 0, y: 0, width: 260, height: 140),
            isOnScreen: false,
            layer: 101
        )
        let data = try JSONEncoder().encode(info)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["layer"] as? Int == 101)
    }
}

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
    func windowRecordParsesCGWindowListEntry() throws {
        let info: [String: Any] = [
            kCGWindowNumber as String: CGWindowID(42),
            kCGWindowOwnerPID as String: pid_t(7),
            kCGWindowOwnerName as String: "App",
            kCGWindowName as String: "Doc",
            kCGWindowBounds as String: CGRect(x: 10, y: 20, width: 300, height: 200).dictionaryRepresentation,
            kCGWindowLayer as String: 101,
            kCGWindowIsOnscreen as String: true,
            kCGWindowAlpha as String: 0.5
        ]
        let record = try #require(WindowRecord(info))
        #expect(record.windowID == 42)
        #expect(record.pid == 7)
        #expect(record.ownerName == "App")
        #expect(record.title == "Doc")
        #expect(record.bounds == CGRect(x: 10, y: 20, width: 300, height: 200))
        #expect(record.layer == 101)
        #expect(record.isOnScreen == true)
        #expect(record.alpha == 0.5)
    }

    @Test
    func windowRecordDefaultsOptionalKeys() throws {
        // CGWindowList omits kCGWindowIsOnscreen for off-screen windows, and the name/owner keys are optional.
        let info: [String: Any] = [
            kCGWindowNumber as String: CGWindowID(1),
            kCGWindowOwnerPID as String: pid_t(2),
            kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 10, height: 10).dictionaryRepresentation
        ]
        let record = try #require(WindowRecord(info))
        #expect(record.isOnScreen == nil)
        #expect(record.title.isEmpty)
        #expect(record.layer == 0)
        #expect(record.alpha == 1)
    }

    @Test
    func windowRecordRejectsMissingRequiredKeys() {
        #expect(WindowRecord([kCGWindowNumber as String: CGWindowID(1)]) == nil)
        #expect(WindowRecord([
            kCGWindowNumber as String: CGWindowID(1),
            kCGWindowOwnerPID as String: pid_t(2)
        ]) == nil)
    }
}

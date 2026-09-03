import AppKit
import CoreGraphics
import Foundation
@testable import peek
import Testing

@Suite("AppManager Tests")
struct AppManagerTests {
    private func window(pid: pid_t, layer: Int = 0) -> WindowInfo {
        WindowInfo(
            windowID: 42,
            ownerName: "Test",
            windowTitle: "Panel",
            pid: pid,
            frame: CGRect(x: 0, y: 0, width: 260, height: 140),
            isOnScreen: true,
            layer: layer
        )
    }

    /// A live non-regular (accessory/prohibited) app to anchor the window-owner tests —
    /// there is always at least one in a login session (Dock, Control Centre, …).
    private var accessoryPID: pid_t? {
        NSWorkspace.shared.runningApplications
            .first { $0.activationPolicy != .regular }?
            .processIdentifier
    }

    @Test
    func listAppsExcludesAccessoryAppsByDefault() throws {
        let pid = try #require(accessoryPID)
        let entries = AppManager.listApps(windows: [window(pid: pid)])
        #expect(!entries.contains { $0.pid == pid })
    }

    @Test
    func listAppsIncludesAccessoryWindowOwnersWhenAsked() throws {
        let pid = try #require(accessoryPID)
        let entries = AppManager.listApps(windows: [window(pid: pid, layer: 101)], includeWindowOwners: true)
        let entry = try #require(entries.first { $0.pid == pid })
        #expect(entry.windows.count == 1)
        #expect(entry.windows[0].layer == 101)
    }

    @Test
    func listAppsExcludesWindowlessAccessoryAppsEvenWhenAsked() throws {
        let pid = try #require(accessoryPID)
        let entries = AppManager.listApps(windows: [], includeWindowOwners: true)
        #expect(!entries.contains { $0.pid == pid })
    }
}

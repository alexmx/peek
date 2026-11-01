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

    // MARK: - bestMatch(_:in:)

    private func app(_ pid: pid_t, _ name: String?, bundle: String? = nil, regular: Bool = true) -> AppManager
        .AppCandidate {
        AppManager.AppCandidate(pid: pid, name: name, bundleID: bundle, isRegular: regular)
    }

    @Test
    func bestMatchPrefersExactNameOverSubstring() {
        let apps = [app(1, "Sticky Notes"), app(2, "Notes")]
        #expect(AppManager.bestMatch("notes", in: apps)?.pid == 2)
    }

    @Test
    func bestMatchExactNameWinsEvenForBackgroundApps() {
        let apps = [app(1, "Dock Helper"), app(2, "Dock", regular: false)]
        #expect(AppManager.bestMatch("Dock", in: apps)?.pid == 2)
    }

    @Test
    func bestMatchPrefersRegularAppsForSubstrings() {
        let apps = [app(1, "Xcode Helper", regular: false), app(2, "Xcode Beta")]
        #expect(AppManager.bestMatch("xcode", in: apps)?.pid == 2)
    }

    @Test
    func bestMatchFallsBackToBackgroundSubstring() {
        let apps = [app(1, "Safari"), app(2, "ControlCenter", regular: false)]
        #expect(AppManager.bestMatch("control", in: apps)?.pid == 2)
    }

    @Test
    func bestMatchUsesBundleIDLast() {
        let apps = [app(1, "Devices", bundle: "com.apple.dt.Devices"), app(2, "Device Hub", bundle: "com.apple.dt.hub")]
        #expect(AppManager.bestMatch("Device Hub", in: apps)?.pid == 2)
        #expect(AppManager.bestMatch("com.apple.dt.Devices", in: apps)?.pid == 1)
    }

    @Test
    func bestMatchReturnsNilWithoutAMatch() {
        #expect(AppManager.bestMatch("Nope", in: [app(1, "Safari", bundle: "com.apple.Safari")]) == nil)
        #expect(AppManager.bestMatch("x", in: []) == nil)
    }
}

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

    private let regularApp = AppManager.RunningApp(
        pid: 10, name: "Notes", bundleID: nil, isRegular: true, isActive: false, isHidden: false
    )
    private let accessoryApp = AppManager.RunningApp(
        pid: 20, name: "Agent", bundleID: nil, isRegular: false, isActive: false, isHidden: false
    )

    @Test
    func listAppsExcludesAccessoryAppsByDefault() {
        let entries = AppManager.listApps([regularApp, accessoryApp], windows: [window(pid: 20)])
        #expect(entries.map(\.pid) == [10])
    }

    @Test
    func listAppsIncludesAccessoryWindowOwnersWhenAsked() throws {
        let entries = AppManager.listApps(
            [regularApp, accessoryApp],
            windows: [window(pid: 20, layer: 101)],
            includeWindowOwners: true
        )
        let entry = try #require(entries.first { $0.pid == 20 })
        #expect(entry.windows.count == 1)
        #expect(entry.windows[0].layer == 101)
    }

    @Test
    func listAppsExcludesWindowlessAccessoryAppsEvenWhenAsked() {
        let entries = AppManager.listApps([regularApp, accessoryApp], windows: [], includeWindowOwners: true)
        #expect(entries.map(\.pid) == [10])
    }

    @Test
    func listAppsCarriesActiveAndHiddenState() throws {
        let app = AppManager.RunningApp(
            pid: 10,
            name: "Notes",
            bundleID: nil,
            isRegular: true,
            isActive: true,
            isHidden: true
        )
        let entry = try #require(AppManager.listApps([app], windows: []).first)
        #expect(entry.isActive && entry.isHidden)
    }

    @Test
    func runningAppsSeesTheLiveSession() async {
        // Read on the main actor; a login session always has Finder and the Dock.
        let names = await AppManager.runningApps().compactMap(\.name)
        #expect(names.contains("Finder") && names.contains("Dock"))
    }

    // MARK: - bestMatch(_:in:)

    private func app(_ pid: pid_t, _ name: String?, bundle: String? = nil, regular: Bool = true) -> AppManager
        .RunningApp {
        AppManager.RunningApp(
            pid: pid,
            name: name,
            bundleID: bundle,
            isRegular: regular,
            isActive: false,
            isHidden: false
        )
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

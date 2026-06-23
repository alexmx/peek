import ArgumentParser
import CoreGraphics
import Foundation
@testable import peek
import Testing

@Suite("WindowTarget Tests")
struct WindowTargetTests {
    // MARK: - Test Data

    let testWindows: [WindowInfo] = [
        WindowInfo(
            windowID: 100,
            ownerName: "Safari",
            windowTitle: "Welcome",
            pid: 1001,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            isOnScreen: true
        ),
        WindowInfo(
            windowID: 101,
            ownerName: "Safari",
            windowTitle: "Settings",
            pid: 1001,
            frame: CGRect(x: 100, y: 100, width: 600, height: 400),
            isOnScreen: false
        ),
        WindowInfo(
            windowID: 200,
            ownerName: "TextEdit",
            windowTitle: "Document.txt",
            pid: 2001,
            frame: CGRect(x: 200, y: 200, width: 500, height: 400),
            isOnScreen: true
        ),
        WindowInfo(
            windowID: 300,
            ownerName: "Finder",
            windowTitle: "Downloads",
            pid: 3001,
            frame: CGRect(x: 50, y: 50, width: 700, height: 500),
            isOnScreen: true
        ),
        WindowInfo(
            windowID: 301,
            ownerName: "Finder",
            windowTitle: "Documents",
            pid: 3001,
            frame: CGRect(x: 150, y: 150, width: 700, height: 500),
            isOnScreen: false
        )
    ]

    // MARK: - findWindow by windowID Tests

    @Test
    func findWindowByIDExists() throws {
        let result = try WindowTarget.findWindow(in: testWindows, windowID: 100)
        #expect(result.windowID == 100)
        #expect(result.pid == 1001)
    }

    @Test
    func findWindowByIDNotFound() {
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: testWindows, windowID: 999)
        }
    }

    @Test
    func findWindowByIDEmptyList() {
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: [], windowID: 100)
        }
    }

    @Test
    func findWindowByIDIgnoresOthers() throws {
        // When windowID is provided, app and pid are ignored
        let result = try WindowTarget.findWindow(in: testWindows, windowID: 100, app: "NonExistent", pid: 9999)
        #expect(result.windowID == 100)
    }

    // MARK: - findWindow by app Tests

    @Test
    func findWindowByAppExact() throws {
        let result = try WindowTarget.findWindow(in: testWindows, app: "TextEdit")
        #expect(result.windowID == 200)
        #expect(result.pid == 2001)
    }

    @Test
    func findWindowByAppCaseInsensitive() throws {
        let result = try WindowTarget.findWindow(in: testWindows, app: "safari")
        #expect(result.pid == 1001)
    }

    @Test
    func findWindowByAppPartial() throws {
        let result = try WindowTarget.findWindow(in: testWindows, app: "Text")
        #expect(result.windowID == 200)
    }

    @Test
    func findWindowByAppPrefersOnScreen() throws {
        // Safari has two windows: 100 (on-screen) and 101 (off-screen)
        let result = try WindowTarget.findWindow(in: testWindows, app: "Safari")
        #expect(result.windowID == 100) // Should prefer on-screen window
        #expect(result.pid == 1001)
    }

    @Test
    func findWindowByAppOffScreenFallback() throws {
        // Create test data with only off-screen windows
        let offScreenWindows = [
            WindowInfo(
                windowID: 400,
                ownerName: "Notes",
                windowTitle: "Note",
                pid: 4001,
                frame: CGRect(x: 0, y: 0, width: 500, height: 400),
                isOnScreen: false
            )
        ]
        let result = try WindowTarget.findWindow(in: offScreenWindows, app: "Notes")
        #expect(result.windowID == 400)
    }

    @Test
    func findWindowByAppNotFound() {
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: testWindows, app: "NonExistent")
        }
    }

    @Test
    func findWindowByAppMultipleMatches() throws {
        // Finder has two windows: 300 (on-screen) and 301 (off-screen)
        let result = try WindowTarget.findWindow(in: testWindows, app: "Finder")
        #expect(result.windowID == 300) // First on-screen match
    }

    // MARK: - findWindow by pid Tests

    @Test
    func findWindowByPIDExists() throws {
        let result = try WindowTarget.findWindow(in: testWindows, pid: 2001)
        #expect(result.windowID == 200)
        #expect(result.pid == 2001)
    }

    @Test
    func findWindowByPIDPrefersOnScreen() throws {
        // Finder PID 3001 has two windows: 300 (on-screen) and 301 (off-screen)
        let result = try WindowTarget.findWindow(in: testWindows, pid: 3001)
        #expect(result.windowID == 300) // Should prefer on-screen
    }

    @Test
    func findWindowByPIDOffScreenFallback() throws {
        let offScreenWindows = [
            WindowInfo(
                windowID: 500,
                ownerName: "App",
                windowTitle: "Window",
                pid: 5001,
                frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                isOnScreen: false
            )
        ]
        let result = try WindowTarget.findWindow(in: offScreenWindows, pid: 5001)
        #expect(result.windowID == 500)
    }

    @Test
    func findWindowByPIDNotFound() {
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: testWindows, pid: 9999)
        }
    }

    @Test
    func findWindowByPIDMultipleWindows() throws {
        // Safari PID 1001 has windows 100 and 101
        let result = try WindowTarget.findWindow(in: testWindows, pid: 1001)
        #expect(result.windowID == 100) // First on-screen match
    }

    // MARK: - findWindow priority Tests

    @Test
    func findWindowPriorityWindowIDOverApp() throws {
        let result = try WindowTarget.findWindow(in: testWindows, windowID: 200, app: "Safari")
        #expect(result.windowID == 200) // windowID wins, not Safari
        #expect(result.pid == 2001)
    }

    @Test
    func findWindowPriorityWindowIDOverPID() throws {
        let result = try WindowTarget.findWindow(in: testWindows, windowID: 200, pid: 1001)
        #expect(result.windowID == 200)
        #expect(result.pid == 2001) // Not 1001
    }

    @Test
    func findWindowPriorityAppOverPID() throws {
        let result = try WindowTarget.findWindow(in: testWindows, app: "TextEdit", pid: 1001)
        #expect(result.windowID == 200) // TextEdit window
        #expect(result.pid == 2001) // Not 1001
    }

    // MARK: - findWindow error cases Tests

    @Test
    func findWindowNoParameters() {
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: testWindows)
        }
    }

    @Test
    func findWindowAllNil() {
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: testWindows, windowID: nil, app: nil, pid: nil)
        }
    }

    @Test
    func findWindowEmptyListWindowID() {
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: [], windowID: 100)
        }
    }

    @Test
    func findWindowEmptyListApp() {
        // findWindow falls back to scanning real running apps (findRunningPID), so the
        // name must not match any live process for the not-found error path to fire.
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: [], app: "NoSuchApp_ZZZ_unlikely_42")
        }
    }

    @Test
    func findWindowEmptyListPID() {
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: [], pid: 1001)
        }
    }

    // MARK: - Edge Cases

    @Test
    func findWindowAppSpecialChars() throws {
        let specialWindows = [
            WindowInfo(
                windowID: 600,
                ownerName: "App-Name.v2",
                windowTitle: "Test",
                pid: 6001,
                frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                isOnScreen: true
            )
        ]
        let result = try WindowTarget.findWindow(in: specialWindows, app: "App-Name")
        #expect(result.windowID == 600)
    }

    @Test
    func findWindowSingleWindow() throws {
        let singleWindow = [testWindows[0]]
        let result = try WindowTarget.findWindow(in: singleWindow, windowID: 100)
        #expect(result.windowID == 100)
    }

    @Test
    func findWindowPreservesInfo() throws {
        let result = try WindowTarget.findWindow(in: testWindows, windowID: 200)
        #expect(result.windowID == 200)
        #expect(result.pid == 2001)
        // Resolved only contains windowID and pid, not full WindowInfo
    }

    @Test
    func findWindowAppSubstring() throws {
        let result = try WindowTarget.findWindow(in: testWindows, app: "Edit")
        #expect(result.windowID == 200) // TextEdit
    }
}

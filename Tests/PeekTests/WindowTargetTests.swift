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

    @Test("findWindow - by windowID exists")
    func findWindowByIDExists() throws {
        let result = try WindowTarget.findWindow(in: testWindows, windowID: 100)
        #expect(result.windowID == 100)
        #expect(result.pid == 1001)
    }

    @Test("findWindow - by windowID not found")
    func findWindowByIDNotFound() {
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: testWindows, windowID: 999)
        }
    }

    @Test("findWindow - by windowID in empty list")
    func findWindowByIDEmptyList() {
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: [], windowID: 100)
        }
    }

    @Test("findWindow - by windowID ignores other params")
    func findWindowByIDIgnoresOthers() throws {
        // When windowID is provided, app and pid are ignored
        let result = try WindowTarget.findWindow(in: testWindows, windowID: 100, app: "NonExistent", pid: 9999)
        #expect(result.windowID == 100)
    }

    // MARK: - findWindow by app Tests

    @Test("findWindow - by app exact match")
    func findWindowByAppExact() throws {
        let result = try WindowTarget.findWindow(in: testWindows, app: "TextEdit")
        #expect(result.windowID == 200)
        #expect(result.pid == 2001)
    }

    @Test("findWindow - by app case insensitive")
    func findWindowByAppCaseInsensitive() throws {
        let result = try WindowTarget.findWindow(in: testWindows, app: "safari")
        #expect(result.pid == 1001)
    }

    @Test("findWindow - by app partial match")
    func findWindowByAppPartial() throws {
        let result = try WindowTarget.findWindow(in: testWindows, app: "Text")
        #expect(result.windowID == 200)
    }

    @Test("findWindow - by app prefers on-screen")
    func findWindowByAppPrefersOnScreen() throws {
        // Safari has two windows: 100 (on-screen) and 101 (off-screen)
        let result = try WindowTarget.findWindow(in: testWindows, app: "Safari")
        #expect(result.windowID == 100) // Should prefer on-screen window
        #expect(result.pid == 1001)
    }

    @Test("findWindow - by app returns off-screen if no on-screen")
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

    @Test("findWindow - by app not found")
    func findWindowByAppNotFound() {
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: testWindows, app: "NonExistent")
        }
    }

    @Test("findWindow - by app multiple matches prefers first on-screen")
    func findWindowByAppMultipleMatches() throws {
        // Finder has two windows: 300 (on-screen) and 301 (off-screen)
        let result = try WindowTarget.findWindow(in: testWindows, app: "Finder")
        #expect(result.windowID == 300) // First on-screen match
    }

    // MARK: - findWindow by pid Tests

    @Test("findWindow - by pid exists")
    func findWindowByPIDExists() throws {
        let result = try WindowTarget.findWindow(in: testWindows, pid: 2001)
        #expect(result.windowID == 200)
        #expect(result.pid == 2001)
    }

    @Test("findWindow - by pid prefers on-screen")
    func findWindowByPIDPrefersOnScreen() throws {
        // Finder PID 3001 has two windows: 300 (on-screen) and 301 (off-screen)
        let result = try WindowTarget.findWindow(in: testWindows, pid: 3001)
        #expect(result.windowID == 300) // Should prefer on-screen
    }

    @Test("findWindow - by pid returns off-screen if no on-screen")
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

    @Test("findWindow - by pid not found")
    func findWindowByPIDNotFound() {
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: testWindows, pid: 9999)
        }
    }

    @Test("findWindow - by pid multiple windows")
    func findWindowByPIDMultipleWindows() throws {
        // Safari PID 1001 has windows 100 and 101
        let result = try WindowTarget.findWindow(in: testWindows, pid: 1001)
        #expect(result.windowID == 100) // First on-screen match
    }

    // MARK: - findWindow priority Tests

    @Test("findWindow - windowID takes priority over app")
    func findWindowPriorityWindowIDOverApp() throws {
        let result = try WindowTarget.findWindow(in: testWindows, windowID: 200, app: "Safari")
        #expect(result.windowID == 200) // windowID wins, not Safari
        #expect(result.pid == 2001)
    }

    @Test("findWindow - windowID takes priority over pid")
    func findWindowPriorityWindowIDOverPID() throws {
        let result = try WindowTarget.findWindow(in: testWindows, windowID: 200, pid: 1001)
        #expect(result.windowID == 200)
        #expect(result.pid == 2001) // Not 1001
    }

    @Test("findWindow - app takes priority over pid")
    func findWindowPriorityAppOverPID() throws {
        let result = try WindowTarget.findWindow(in: testWindows, app: "TextEdit", pid: 1001)
        #expect(result.windowID == 200) // TextEdit window
        #expect(result.pid == 2001) // Not 1001
    }

    // MARK: - findWindow error cases Tests

    @Test("findWindow - no parameters throws")
    func findWindowNoParameters() {
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: testWindows)
        }
    }

    @Test("findWindow - all nil parameters throws")
    func findWindowAllNil() {
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: testWindows, windowID: nil, app: nil, pid: nil)
        }
    }

    @Test("findWindow - empty windows list with windowID")
    func findWindowEmptyListWindowID() {
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: [], windowID: 100)
        }
    }

    @Test("findWindow - empty windows list with app")
    func findWindowEmptyListApp() {
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: [], app: "Safari")
        }
    }

    @Test("findWindow - empty windows list with pid")
    func findWindowEmptyListPID() {
        #expect(throws: ValidationError.self) {
            try WindowTarget.findWindow(in: [], pid: 1001)
        }
    }

    // MARK: - Edge Cases

    @Test("findWindow - app with special characters")
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

    @Test("findWindow - single window matches all criteria")
    func findWindowSingleWindow() throws {
        let singleWindow = [testWindows[0]]
        let result = try WindowTarget.findWindow(in: singleWindow, windowID: 100)
        #expect(result.windowID == 100)
    }

    @Test("findWindow - preserves exact window info")
    func findWindowPreservesInfo() throws {
        let result = try WindowTarget.findWindow(in: testWindows, windowID: 200)
        #expect(result.windowID == 200)
        #expect(result.pid == 2001)
        // Resolved only contains windowID and pid, not full WindowInfo
    }

    @Test("findWindow - app substring in middle")
    func findWindowAppSubstring() throws {
        let result = try WindowTarget.findWindow(in: testWindows, app: "Edit")
        #expect(result.windowID == 200) // TextEdit
    }
}

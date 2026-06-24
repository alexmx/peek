import ApplicationServices
import Foundation
@testable import peek
import Testing

@Suite("PeekError Tests")
struct PeekErrorTests {
    // MARK: - Error Description Tests

    @Test
    func windowNotFoundDescription() throws {
        let error = PeekError.windowNotFound(12345)
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("12345")))
        #expect(try #require(description?.contains("window")))
        #expect(try #require(description?.contains("peek apps")))
    }

    @Test
    func accessibilityNotTrustedDescription() throws {
        let error = PeekError.accessibilityNotTrusted
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("Accessibility")))
        #expect(try #require(description?.contains("permission")))
        #expect(try #require(description?.contains("System Settings")))
    }

    @Test
    func noWindowsDescription() throws {
        let error = PeekError.noWindows
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("window")))
        #expect(try #require(description?.contains("application")))
    }

    @Test
    func failedToWriteDescription() throws {
        let testPath = "/tmp/test.png"
        let error = PeekError.failedToWrite(testPath)
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains(testPath)))
        #expect(try #require(description?.contains("Failed to write")))
    }

    @Test
    func elementNotFoundDescription() throws {
        let error = PeekError.elementNotFound
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("element")))
        #expect(try #require(description?.contains("found")))
    }

    @Test
    func actionFailedDescription() throws {
        let error = PeekError.actionFailed("Press", .actionUnsupported)
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("Press")))
        #expect(try #require(description?.contains("action")))
        #expect(try #require(description?.contains("not supported")))
    }

    @Test
    func actionFailedDifferentErrors() throws {
        let testCases: [(String, AXError, String)] = [
            ("Press", .actionUnsupported, "not supported"),
            ("Confirm", .cannotComplete, "cannot complete"),
            ("ShowMenu", .invalidUIElement, "invalid"),
            ("Raise", .attributeUnsupported, "unsupported")
        ]

        for (action, axError, expectedFragment) in testCases {
            let error = PeekError.actionFailed(action, axError)
            let description = error.errorDescription
            #expect(description != nil)
            #expect(try #require(description?.contains(action)))
            #expect(try #require(description?.localizedCaseInsensitiveContains(expectedFragment)))
        }
    }

    @Test
    func noMenuBarDescription() throws {
        let error = PeekError.noMenuBar(54321)
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("54321")))
        #expect(try #require(description?.contains("menu bar")))
    }

    @Test
    func menuItemNotFoundDescription() throws {
        let error = PeekError.menuItemNotFound("File > Open")
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("File > Open")))
        #expect(try #require(description?.contains("menu item")))
    }

    @Test
    func screenCaptureNotGrantedDescription() throws {
        let error = PeekError.screenCaptureNotGranted
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("Screen Recording")))
        #expect(try #require(description?.contains("permission")))
        #expect(try #require(description?.contains("System Settings")))
    }

    @Test
    func invalidCropRegionDescription() throws {
        let error = PeekError.invalidCropRegion
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("Crop")))
        #expect(try #require(description?.contains("outside")))
        #expect(try #require(description?.contains("bounds")))
    }

    @Test
    func captureFailedDescription() throws {
        let error = PeekError.captureFailed
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.localizedCaseInsensitiveContains("time")))
        #expect(try #require(description?.contains("peek doctor")))
    }

    @Test
    func encodingFailedDescription() throws {
        let error = PeekError.encodingFailed
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("encode")))
        #expect(try #require(description?.contains("JSON")))
    }

    @Test
    func activationFailedDescription() throws {
        let error = PeekError.activationFailed(54321, "TestApp")
        let description = try #require(error.errorDescription)
        #expect(description.contains("TestApp"))
        #expect(description.contains("54321"))
        #expect(description.localizedCaseInsensitiveContains("foreground"))
        #expect(description.contains("Dock"))
    }

    @Test
    func unsupportedActionWithSupported() throws {
        let error = PeekError.unsupportedAction("AXShowMenu", supported: ["AXPress", "AXConfirm"])
        let description = try #require(error.errorDescription)
        #expect(description.contains("AXShowMenu"))
        #expect(description.contains("AXPress"))
        #expect(description.contains("AXConfirm"))
        #expect(description.localizedCaseInsensitiveContains("not supported"))
    }

    @Test
    func unsupportedActionWithEmpty() throws {
        let error = PeekError.unsupportedAction("AXPress", supported: [])
        let description = try #require(error.errorDescription)
        #expect(description.contains("AXPress"))
        #expect(description.localizedCaseInsensitiveContains("no ax actions"))
        #expect(description.contains("peek_click"))
    }

    @Test
    func timeoutDescription() throws {
        let error = PeekError.timeout("peek_find", 20)
        let description = try #require(error.errorDescription)
        #expect(description.contains("peek_find"))
        #expect(description.contains("20"))
        #expect(description.localizedCaseInsensitiveContains("timed out"))
        #expect(description.localizedCaseInsensitiveContains("retry") || description
            .localizedCaseInsensitiveContains("depth"))
    }

    @Test
    func windowHiddenDescription() throws {
        let error = PeekError.windowHidden(42)
        let description = try #require(error.errorDescription)
        #expect(description.contains("42"))
        #expect(description.localizedCaseInsensitiveContains("hidden"))
        #expect(description.contains("peek_activate"))
    }

    @Test
    func appNotFoundDescription() throws {
        let error = PeekError.appNotFound("NoSuchApp")
        let description = try #require(error.errorDescription)
        #expect(description.contains("NoSuchApp"))
        #expect(description.contains("bundle_id"))
        #expect(description.localizedCaseInsensitiveContains("name"))
        #expect(description.contains(".app"))
    }

    @Test
    func launchFailedDescription() throws {
        let error = PeekError.launchFailed("TestApp", "process exited")
        let description = try #require(error.errorDescription)
        #expect(description.contains("TestApp"))
        #expect(description.contains("process exited"))
    }

    // MARK: - All Errors Have Descriptions

    @Test
    func allErrorsHaveDescriptions() throws {
        let errors: [PeekError] = [
            .windowNotFound(123),
            .accessibilityNotTrusted,
            .noWindows,
            .failedToWrite("/tmp/test"),
            .elementNotFound,
            .actionFailed("Press", .actionUnsupported),
            .noMenuBar(999),
            .menuItemNotFound("Test"),
            .screenCaptureNotGranted,
            .invalidCropRegion,
            .captureFailed,
            .encodingFailed,
            .activationFailed(123, "TestApp"),
            .unsupportedAction("AXShowMenu", supported: ["AXPress"]),
            .timeout("peek_tree", 20),
            .windowHidden(99),
            .appNotFound("XYZ"),
            .launchFailed("XYZ", "oops")
        ]

        for error in errors {
            let description = error.errorDescription
            #expect(description != nil, "Error \(error) should have a description")
            #expect(try !#require(description?.isEmpty), "Error \(error) description should not be empty")
        }
    }

    // MARK: - Error Context

    @Test
    func permissionErrorsMentionSystemSettings() throws {
        let permissionErrors: [PeekError] = [
            .accessibilityNotTrusted,
            .screenCaptureNotGranted
        ]

        for error in permissionErrors {
            let description = try #require(error.errorDescription)
            #expect(description.contains("System Settings"), "Permission error should mention System Settings")
            #expect(description.contains("Privacy"), "Permission error should mention Privacy")
        }
    }

    @Test
    func errorMessagesProvideGuidance() throws {
        let testCases: [(PeekError, String)] = [
            (.windowNotFound(123), "peek apps"),
            (.accessibilityNotTrusted, "System Settings"),
            (.screenCaptureNotGranted, "System Settings"),
            (.captureFailed, "peek doctor"),
            (.actionFailed("Press", .actionUnsupported), "different action")
        ]

        for (error, expectedGuidance) in testCases {
            let description = try #require(error.errorDescription)
            #expect(
                description.contains(expectedGuidance),
                "Error \(error) should provide guidance: '\(expectedGuidance)'"
            )
        }
    }

    @Test
    func noTextContentDescription() throws {
        let description = try #require(PeekError.noTextContent.errorDescription)
        #expect(description.contains("readable text"))
        #expect(description.contains("AXStringForRange"))
    }

    @Test
    func substringNotFoundDescription() throws {
        let description = try #require(PeekError.substringNotFound("Submit").errorDescription)
        #expect(description.contains("Submit"))
        #expect(description.contains("not found"))
        #expect(description.contains("case-sensitive"))
    }

    @Test
    func coordinateOffTargetDescription() throws {
        let error = PeekError.coordinateOffTarget(x: 100, y: 490, target: "CodeChat", actual: "Ghostty")
        let description = try #require(error.errorDescription)
        #expect(description.contains("(100, 490)"))
        #expect(description.contains("CodeChat"))
        #expect(description.contains("Ghostty"))
        #expect(description.contains("window_id"))
    }

    @Test
    func descriptionMatchesErrorDescription() throws {
        // The MCP server renders errors via String(describing:); CustomStringConvertible
        // must route that to errorDescription instead of the bare case name.
        let cases: [PeekError] = [
            .noTextContent, .substringNotFound("x"), .screenCaptureNotGranted, .elementNotFound, .windowNotFound(7),
            .coordinateOffTarget(x: 1, y: 2, target: "A", actual: "B")
        ]
        for error in cases {
            let expected = try #require(error.errorDescription)
            #expect(String(describing: error) == expected)
            #expect(error.description == expected)
        }
        // Specifically not the raw enum case label.
        #expect(String(describing: PeekError.screenCaptureNotGranted) != "screenCaptureNotGranted")
    }
}

import ApplicationServices
import Foundation
@testable import peek
import Testing

@Suite("PeekError Tests")
struct PeekErrorTests {
    // MARK: - Error Description Tests

    @Test("windowNotFound - includes window ID")
    func windowNotFoundDescription() throws {
        let error = PeekError.windowNotFound(12345)
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("12345")))
        #expect(try #require(description?.contains("window")))
        #expect(try #require(description?.contains("peek apps")))
    }

    @Test("accessibilityNotTrusted - mentions permission")
    func accessibilityNotTrustedDescription() throws {
        let error = PeekError.accessibilityNotTrusted
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("Accessibility")))
        #expect(try #require(description?.contains("permission")))
        #expect(try #require(description?.contains("System Settings")))
    }

    @Test("noWindows - clear message")
    func noWindowsDescription() throws {
        let error = PeekError.noWindows
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("window")))
        #expect(try #require(description?.contains("application")))
    }

    @Test("failedToWrite - includes path")
    func failedToWriteDescription() throws {
        let testPath = "/tmp/test.png"
        let error = PeekError.failedToWrite(testPath)
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains(testPath)))
        #expect(try #require(description?.contains("Failed to write")))
    }

    @Test("elementNotFound - clear message")
    func elementNotFoundDescription() throws {
        let error = PeekError.elementNotFound
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("element")))
        #expect(try #require(description?.contains("found")))
    }

    @Test("actionFailed - includes action name and error")
    func actionFailedDescription() throws {
        let error = PeekError.actionFailed("Press", .actionUnsupported)
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("Press")))
        #expect(try #require(description?.contains("action")))
        #expect(try #require(description?.contains("not supported")))
    }

    @Test("actionFailed - different AX errors")
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

    @Test("noMenuBar - includes PID")
    func noMenuBarDescription() throws {
        let error = PeekError.noMenuBar(54321)
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("54321")))
        #expect(try #require(description?.contains("menu bar")))
    }

    @Test("menuItemNotFound - includes title")
    func menuItemNotFoundDescription() throws {
        let error = PeekError.menuItemNotFound("File > Open")
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("File > Open")))
        #expect(try #require(description?.contains("menu item")))
    }

    @Test("screenCaptureNotGranted - mentions permission")
    func screenCaptureNotGrantedDescription() throws {
        let error = PeekError.screenCaptureNotGranted
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("Screen Recording")))
        #expect(try #require(description?.contains("permission")))
        #expect(try #require(description?.contains("System Settings")))
    }

    @Test("invalidCropRegion - clear message")
    func invalidCropRegionDescription() throws {
        let error = PeekError.invalidCropRegion
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("Crop")))
        #expect(try #require(description?.contains("outside")))
        #expect(try #require(description?.contains("bounds")))
    }

    @Test("captureFailed - mentions timeout and doctor command")
    func captureFailedDescription() throws {
        let error = PeekError.captureFailed
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.localizedCaseInsensitiveContains("time")))
        #expect(try #require(description?.contains("peek doctor")))
    }

    @Test("encodingFailed - clear message")
    func encodingFailedDescription() throws {
        let error = PeekError.encodingFailed
        let description = error.errorDescription
        #expect(description != nil)
        #expect(try #require(description?.contains("encode")))
        #expect(try #require(description?.contains("JSON")))
    }

    // MARK: - All Errors Have Descriptions

    @Test("all error cases have non-empty descriptions")
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
            .encodingFailed
        ]

        for error in errors {
            let description = error.errorDescription
            #expect(description != nil, "Error \(error) should have a description")
            #expect(try !(#require(description?.isEmpty)), "Error \(error) description should not be empty")
        }
    }

    // MARK: - Error Context

    @Test("permission errors mention System Settings")
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

    @Test("error messages provide actionable guidance")
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
}

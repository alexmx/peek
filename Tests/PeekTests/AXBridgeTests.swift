import Foundation
@testable import peek
import Testing

@Suite("AXBridge Tests")
struct AXBridgeTests {
    // MARK: - stripAXPrefix() Tests

    @Test
    func stripAXPrefixRemoves() {
        #expect(AXBridge.stripAXPrefix("AXButton") == "Button")
        #expect(AXBridge.stripAXPrefix("AXWindow") == "Window")
        #expect(AXBridge.stripAXPrefix("AXTextField") == "TextField")
        #expect(AXBridge.stripAXPrefix("AXMenuItem") == "MenuItem")
    }

    @Test
    func stripAXPrefixAlreadyStripped() {
        #expect(AXBridge.stripAXPrefix("Button") == "Button")
        #expect(AXBridge.stripAXPrefix("Window") == "Window")
        #expect(AXBridge.stripAXPrefix("TextField") == "TextField")
    }

    @Test
    func stripAXPrefixEdgeCases() {
        #expect(AXBridge.stripAXPrefix("AX") == "")
        #expect(AXBridge.stripAXPrefix("A") == "A")
        #expect(AXBridge.stripAXPrefix("") == "")
        #expect(AXBridge.stripAXPrefix("ax") == "ax") // lowercase not stripped
        #expect(AXBridge.stripAXPrefix("AxButton") == "AxButton") // Mixed case not stripped
    }

    @Test
    func stripAXPrefixPreservesCase() {
        #expect(AXBridge.stripAXPrefix("AXbutton") == "button")
        #expect(AXBridge.stripAXPrefix("AXBUTTON") == "BUTTON")
    }

    @Test
    func stripAXPrefixNotRecursive() {
        #expect(AXBridge.stripAXPrefix("AXAXButton") == "AXButton")
    }

    @Test
    func stripAXPrefixSpecialChars() {
        #expect(AXBridge.stripAXPrefix("AX_Button") == "_Button")
        #expect(AXBridge.stripAXPrefix("AX123") == "123")
    }

    @Test
    func stripAXPrefixRealRoles() {
        let roles = [
            ("AXApplication", "Application"),
            ("AXWindow", "Window"),
            ("AXButton", "Button"),
            ("AXTextField", "TextField"),
            ("AXStaticText", "StaticText"),
            ("AXGroup", "Group"),
            ("AXScrollArea", "ScrollArea"),
            ("AXMenuItem", "MenuItem"),
            ("AXMenuBar", "MenuBar"),
            ("AXMenu", "Menu")
        ]

        for (input, expected) in roles {
            #expect(AXBridge.stripAXPrefix(input) == expected)
        }
    }

    // MARK: - ensureAXPrefix() Tests

    @Test
    func ensureAXPrefixAdds() {
        #expect(AXBridge.ensureAXPrefix("Button") == "AXButton")
        #expect(AXBridge.ensureAXPrefix("Window") == "AXWindow")
        #expect(AXBridge.ensureAXPrefix("TextField") == "AXTextField")
        #expect(AXBridge.ensureAXPrefix("MenuItem") == "AXMenuItem")
    }

    @Test
    func ensureAXPrefixAlreadyHas() {
        #expect(AXBridge.ensureAXPrefix("AXButton") == "AXButton")
        #expect(AXBridge.ensureAXPrefix("AXWindow") == "AXWindow")
        #expect(AXBridge.ensureAXPrefix("AXTextField") == "AXTextField")
    }

    @Test
    func ensureAXPrefixIdempotent() {
        let result1 = AXBridge.ensureAXPrefix("Button")
        let result2 = AXBridge.ensureAXPrefix(result1)
        #expect(result1 == result2)
        #expect(result1 == "AXButton")
    }

    @Test
    func ensureAXPrefixEdgeCases() {
        #expect(AXBridge.ensureAXPrefix("") == "AX")
        #expect(AXBridge.ensureAXPrefix("AX") == "AX")
        #expect(AXBridge.ensureAXPrefix("A") == "AXA")
        #expect(AXBridge.ensureAXPrefix("ax") == "AXax") // lowercase not recognized
    }

    @Test
    func ensureAXPrefixPreservesCase() {
        #expect(AXBridge.ensureAXPrefix("button") == "AXbutton")
        #expect(AXBridge.ensureAXPrefix("BUTTON") == "AXBUTTON")
    }

    @Test
    func ensureAXPrefixSpecialChars() {
        #expect(AXBridge.ensureAXPrefix("_Button") == "AX_Button")
        #expect(AXBridge.ensureAXPrefix("123") == "AX123")
    }

    @Test
    func ensureAXPrefixRealRoles() {
        let roles = [
            ("Application", "AXApplication"),
            ("Window", "AXWindow"),
            ("Button", "AXButton"),
            ("TextField", "AXTextField"),
            ("StaticText", "AXStaticText"),
            ("Group", "AXGroup"),
            ("ScrollArea", "AXScrollArea"),
            ("MenuItem", "AXMenuItem"),
            ("MenuBar", "AXMenuBar"),
            ("Menu", "AXMenu")
        ]

        for (input, expected) in roles {
            #expect(AXBridge.ensureAXPrefix(input) == expected)
        }
    }

    // MARK: - Round-trip Tests

    @Test
    func roundtripStripThenEnsure() {
        let original = "AXButton"
        let stripped = AXBridge.stripAXPrefix(original)
        let ensured = AXBridge.ensureAXPrefix(stripped)
        #expect(ensured == original)
    }

    @Test
    func roundtripEnsureThenStrip() {
        let original = "Button"
        let ensured = AXBridge.ensureAXPrefix(original)
        let stripped = AXBridge.stripAXPrefix(ensured)
        #expect(stripped == original)
    }

    @Test
    func roundtripMultipleCycles() {
        var current = "Window"

        for _ in 0..<5 {
            current = AXBridge.ensureAXPrefix(current)
            current = AXBridge.stripAXPrefix(current)
        }

        #expect(current == "Window")
    }

    // MARK: - Unicode and Edge Cases

    @Test
    func stripAXPrefixUnicode() {
        #expect(AXBridge.stripAXPrefix("AX文字") == "文字")
        #expect(AXBridge.stripAXPrefix("AX🔥") == "🔥")
    }

    @Test
    func ensureAXPrefixUnicode() {
        #expect(AXBridge.ensureAXPrefix("文字") == "AX文字")
        #expect(AXBridge.ensureAXPrefix("🔥") == "AX🔥")
    }
}

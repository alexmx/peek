import Foundation
@testable import peek
import Testing

@Suite("AXBridge Tests")
struct AXBridgeTests {
    // MARK: - stripAXPrefix() Tests

    @Test("stripAXPrefix - removes AX prefix")
    func stripAXPrefixRemoves() {
        #expect(AXBridge.stripAXPrefix("AXButton") == "Button")
        #expect(AXBridge.stripAXPrefix("AXWindow") == "Window")
        #expect(AXBridge.stripAXPrefix("AXTextField") == "TextField")
        #expect(AXBridge.stripAXPrefix("AXMenuItem") == "MenuItem")
    }

    @Test("stripAXPrefix - already stripped")
    func stripAXPrefixAlreadyStripped() {
        #expect(AXBridge.stripAXPrefix("Button") == "Button")
        #expect(AXBridge.stripAXPrefix("Window") == "Window")
        #expect(AXBridge.stripAXPrefix("TextField") == "TextField")
    }

    @Test("stripAXPrefix - edge cases")
    func stripAXPrefixEdgeCases() {
        #expect(AXBridge.stripAXPrefix("AX") == "")
        #expect(AXBridge.stripAXPrefix("A") == "A")
        #expect(AXBridge.stripAXPrefix("") == "")
        #expect(AXBridge.stripAXPrefix("ax") == "ax") // lowercase not stripped
        #expect(AXBridge.stripAXPrefix("AxButton") == "AxButton") // Mixed case not stripped
    }

    @Test("stripAXPrefix - preserves case after prefix")
    func stripAXPrefixPreservesCase() {
        #expect(AXBridge.stripAXPrefix("AXbutton") == "button")
        #expect(AXBridge.stripAXPrefix("AXBUTTON") == "BUTTON")
    }

    @Test("stripAXPrefix - multiple AX not recursively stripped")
    func stripAXPrefixNotRecursive() {
        #expect(AXBridge.stripAXPrefix("AXAXButton") == "AXButton")
    }

    @Test("stripAXPrefix - special characters")
    func stripAXPrefixSpecialChars() {
        #expect(AXBridge.stripAXPrefix("AX_Button") == "_Button")
        #expect(AXBridge.stripAXPrefix("AX123") == "123")
    }

    @Test("stripAXPrefix - real role names")
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

    @Test("ensureAXPrefix - adds prefix")
    func ensureAXPrefixAdds() {
        #expect(AXBridge.ensureAXPrefix("Button") == "AXButton")
        #expect(AXBridge.ensureAXPrefix("Window") == "AXWindow")
        #expect(AXBridge.ensureAXPrefix("TextField") == "AXTextField")
        #expect(AXBridge.ensureAXPrefix("MenuItem") == "AXMenuItem")
    }

    @Test("ensureAXPrefix - already has prefix")
    func ensureAXPrefixAlreadyHas() {
        #expect(AXBridge.ensureAXPrefix("AXButton") == "AXButton")
        #expect(AXBridge.ensureAXPrefix("AXWindow") == "AXWindow")
        #expect(AXBridge.ensureAXPrefix("AXTextField") == "AXTextField")
    }

    @Test("ensureAXPrefix - idempotent")
    func ensureAXPrefixIdempotent() {
        let result1 = AXBridge.ensureAXPrefix("Button")
        let result2 = AXBridge.ensureAXPrefix(result1)
        #expect(result1 == result2)
        #expect(result1 == "AXButton")
    }

    @Test("ensureAXPrefix - edge cases")
    func ensureAXPrefixEdgeCases() {
        #expect(AXBridge.ensureAXPrefix("") == "AX")
        #expect(AXBridge.ensureAXPrefix("AX") == "AX")
        #expect(AXBridge.ensureAXPrefix("A") == "AXA")
        #expect(AXBridge.ensureAXPrefix("ax") == "AXax") // lowercase not recognized
    }

    @Test("ensureAXPrefix - preserves original case")
    func ensureAXPrefixPreservesCase() {
        #expect(AXBridge.ensureAXPrefix("button") == "AXbutton")
        #expect(AXBridge.ensureAXPrefix("BUTTON") == "AXBUTTON")
    }

    @Test("ensureAXPrefix - special characters")
    func ensureAXPrefixSpecialChars() {
        #expect(AXBridge.ensureAXPrefix("_Button") == "AX_Button")
        #expect(AXBridge.ensureAXPrefix("123") == "AX123")
    }

    @Test("ensureAXPrefix - real role names")
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

    @Test("roundtrip - strip then ensure")
    func roundtripStripThenEnsure() {
        let original = "AXButton"
        let stripped = AXBridge.stripAXPrefix(original)
        let ensured = AXBridge.ensureAXPrefix(stripped)
        #expect(ensured == original)
    }

    @Test("roundtrip - ensure then strip")
    func roundtripEnsureThenStrip() {
        let original = "Button"
        let ensured = AXBridge.ensureAXPrefix(original)
        let stripped = AXBridge.stripAXPrefix(ensured)
        #expect(stripped == original)
    }

    @Test("roundtrip - multiple cycles")
    func roundtripMultipleCycles() {
        var current = "Window"

        for _ in 0..<5 {
            current = AXBridge.ensureAXPrefix(current)
            current = AXBridge.stripAXPrefix(current)
        }

        #expect(current == "Window")
    }

    // MARK: - Unicode and Edge Cases

    @Test("stripAXPrefix - unicode characters")
    func stripAXPrefixUnicode() {
        #expect(AXBridge.stripAXPrefix("AX文字") == "文字")
        #expect(AXBridge.stripAXPrefix("AX🔥") == "🔥")
    }

    @Test("ensureAXPrefix - unicode characters")
    func ensureAXPrefixUnicode() {
        #expect(AXBridge.ensureAXPrefix("文字") == "AX文字")
        #expect(AXBridge.ensureAXPrefix("🔥") == "AX🔥")
    }
}

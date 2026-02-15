import Foundation
@testable import peek
import Testing

@Suite("AXElement Tests")
struct AXElementTests {
    // MARK: - stripAXPrefix() Tests

    @Test("stripAXPrefix - removes AX prefix")
    func stripAXPrefixRemoves() {
        #expect(AXElement.stripAXPrefix("AXButton") == "Button")
        #expect(AXElement.stripAXPrefix("AXWindow") == "Window")
        #expect(AXElement.stripAXPrefix("AXTextField") == "TextField")
        #expect(AXElement.stripAXPrefix("AXMenuItem") == "MenuItem")
    }

    @Test("stripAXPrefix - already stripped")
    func stripAXPrefixAlreadyStripped() {
        #expect(AXElement.stripAXPrefix("Button") == "Button")
        #expect(AXElement.stripAXPrefix("Window") == "Window")
        #expect(AXElement.stripAXPrefix("TextField") == "TextField")
    }

    @Test("stripAXPrefix - edge cases")
    func stripAXPrefixEdgeCases() {
        #expect(AXElement.stripAXPrefix("AX") == "")
        #expect(AXElement.stripAXPrefix("A") == "A")
        #expect(AXElement.stripAXPrefix("") == "")
        #expect(AXElement.stripAXPrefix("ax") == "ax") // lowercase not stripped
        #expect(AXElement.stripAXPrefix("AxButton") == "AxButton") // Mixed case not stripped
    }

    @Test("stripAXPrefix - preserves case after prefix")
    func stripAXPrefixPreservesCase() {
        #expect(AXElement.stripAXPrefix("AXbutton") == "button")
        #expect(AXElement.stripAXPrefix("AXBUTTON") == "BUTTON")
    }

    @Test("stripAXPrefix - multiple AX not recursively stripped")
    func stripAXPrefixNotRecursive() {
        #expect(AXElement.stripAXPrefix("AXAXButton") == "AXButton")
    }

    @Test("stripAXPrefix - special characters")
    func stripAXPrefixSpecialChars() {
        #expect(AXElement.stripAXPrefix("AX_Button") == "_Button")
        #expect(AXElement.stripAXPrefix("AX123") == "123")
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
            #expect(AXElement.stripAXPrefix(input) == expected)
        }
    }

    // MARK: - ensureAXPrefix() Tests

    @Test("ensureAXPrefix - adds prefix")
    func ensureAXPrefixAdds() {
        #expect(AXElement.ensureAXPrefix("Button") == "AXButton")
        #expect(AXElement.ensureAXPrefix("Window") == "AXWindow")
        #expect(AXElement.ensureAXPrefix("TextField") == "AXTextField")
        #expect(AXElement.ensureAXPrefix("MenuItem") == "AXMenuItem")
    }

    @Test("ensureAXPrefix - already has prefix")
    func ensureAXPrefixAlreadyHas() {
        #expect(AXElement.ensureAXPrefix("AXButton") == "AXButton")
        #expect(AXElement.ensureAXPrefix("AXWindow") == "AXWindow")
        #expect(AXElement.ensureAXPrefix("AXTextField") == "AXTextField")
    }

    @Test("ensureAXPrefix - idempotent")
    func ensureAXPrefixIdempotent() {
        let result1 = AXElement.ensureAXPrefix("Button")
        let result2 = AXElement.ensureAXPrefix(result1)
        #expect(result1 == result2)
        #expect(result1 == "AXButton")
    }

    @Test("ensureAXPrefix - edge cases")
    func ensureAXPrefixEdgeCases() {
        #expect(AXElement.ensureAXPrefix("") == "AX")
        #expect(AXElement.ensureAXPrefix("AX") == "AX")
        #expect(AXElement.ensureAXPrefix("A") == "AXA")
        #expect(AXElement.ensureAXPrefix("ax") == "AXax") // lowercase not recognized
    }

    @Test("ensureAXPrefix - preserves original case")
    func ensureAXPrefixPreservesCase() {
        #expect(AXElement.ensureAXPrefix("button") == "AXbutton")
        #expect(AXElement.ensureAXPrefix("BUTTON") == "AXBUTTON")
    }

    @Test("ensureAXPrefix - special characters")
    func ensureAXPrefixSpecialChars() {
        #expect(AXElement.ensureAXPrefix("_Button") == "AX_Button")
        #expect(AXElement.ensureAXPrefix("123") == "AX123")
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
            #expect(AXElement.ensureAXPrefix(input) == expected)
        }
    }

    // MARK: - Round-trip Tests

    @Test("roundtrip - strip then ensure")
    func roundtripStripThenEnsure() {
        let original = "AXButton"
        let stripped = AXElement.stripAXPrefix(original)
        let ensured = AXElement.ensureAXPrefix(stripped)
        #expect(ensured == original)
    }

    @Test("roundtrip - ensure then strip")
    func roundtripEnsureThenStrip() {
        let original = "Button"
        let ensured = AXElement.ensureAXPrefix(original)
        let stripped = AXElement.stripAXPrefix(ensured)
        #expect(stripped == original)
    }

    @Test("roundtrip - multiple cycles")
    func roundtripMultipleCycles() {
        var current = "Window"

        for _ in 0..<5 {
            current = AXElement.ensureAXPrefix(current)
            current = AXElement.stripAXPrefix(current)
        }

        #expect(current == "Window")
    }

    // MARK: - Unicode and Edge Cases

    @Test("stripAXPrefix - unicode characters")
    func stripAXPrefixUnicode() {
        #expect(AXElement.stripAXPrefix("AX文字") == "文字")
        #expect(AXElement.stripAXPrefix("AX🔥") == "🔥")
    }

    @Test("ensureAXPrefix - unicode characters")
    func ensureAXPrefixUnicode() {
        #expect(AXElement.ensureAXPrefix("文字") == "AX文字")
        #expect(AXElement.ensureAXPrefix("🔥") == "AX🔥")
    }
}

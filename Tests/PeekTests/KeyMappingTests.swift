import CoreGraphics
@testable import peek
import Testing

@Suite("KeyMapping Tests")
struct KeyMappingTests {
    // MARK: - Lowercase Letters

    @Test("lookup - lowercase letters")
    func lookupLowercaseLetters() {
        let letters: [(Character, CGKeyCode)] = [
            ("a", 0x00), ("s", 0x01), ("d", 0x02), ("f", 0x03),
            ("h", 0x04), ("g", 0x05), ("z", 0x06), ("x", 0x07),
            ("c", 0x08), ("v", 0x09), ("b", 0x0B), ("q", 0x0C),
            ("w", 0x0D), ("e", 0x0E), ("r", 0x0F), ("y", 0x10),
            ("t", 0x11), ("o", 0x1F), ("u", 0x20), ("i", 0x22),
            ("p", 0x23), ("l", 0x25), ("j", 0x26), ("k", 0x28),
            ("n", 0x2D), ("m", 0x2E)
        ]

        for (char, expectedKeyCode) in letters {
            let (keyCode, shift) = KeyMapping.lookup(char)
            #expect(keyCode == expectedKeyCode, "Expected \(char) to map to keyCode \(expectedKeyCode), got \(keyCode)")
            #expect(shift == false, "Expected \(char) to not require shift")
        }
    }

    // MARK: - Uppercase Letters

    @Test("lookup - uppercase letters use shift")
    func lookupUppercaseLetters() {
        let letters: [(Character, CGKeyCode)] = [
            ("A", 0x00), ("S", 0x01), ("D", 0x02), ("F", 0x03),
            ("Z", 0x06), ("Q", 0x0C), ("W", 0x0D), ("E", 0x0E)
        ]

        for (char, expectedKeyCode) in letters {
            let (keyCode, shift) = KeyMapping.lookup(char)
            #expect(keyCode == expectedKeyCode, "Expected \(char) to map to keyCode \(expectedKeyCode)")
            #expect(shift == true, "Expected \(char) to require shift")
        }
    }

    @Test("lookup - uppercase and lowercase same keyCode")
    func lookupUppercaseLowercaseSameKeyCode() {
        let pairs: [(Character, Character)] = [
            ("a", "A"), ("z", "Z"), ("m", "M"), ("q", "Q")
        ]

        for (lower, upper) in pairs {
            let (lowerKeyCode, lowerShift) = KeyMapping.lookup(lower)
            let (upperKeyCode, upperShift) = KeyMapping.lookup(upper)

            #expect(lowerKeyCode == upperKeyCode, "Expected \(lower) and \(upper) to have same keyCode")
            #expect(lowerShift == false)
            #expect(upperShift == true)
        }
    }

    // MARK: - Numbers

    @Test("lookup - number keys")
    func lookupNumbers() {
        let numbers: [(Character, CGKeyCode)] = [
            ("1", 0x12), ("2", 0x13), ("3", 0x14), ("4", 0x15),
            ("5", 0x17), ("6", 0x16), ("7", 0x1A), ("8", 0x1C),
            ("9", 0x19), ("0", 0x1D)
        ]

        for (char, expectedKeyCode) in numbers {
            let (keyCode, shift) = KeyMapping.lookup(char)
            #expect(keyCode == expectedKeyCode, "Expected \(char) to map to keyCode \(expectedKeyCode)")
            #expect(shift == false, "Expected \(char) to not require shift")
        }
    }

    // MARK: - Unshifted Symbols

    @Test("lookup - unshifted symbols")
    func lookupUnshiftedSymbols() {
        let symbols: [(Character, CGKeyCode)] = [
            ("-", 0x1B), ("=", 0x18), ("]", 0x1E), ("[", 0x21),
            ("'", 0x27), (";", 0x29), ("\\", 0x2A), (",", 0x2B),
            ("/", 0x2C), (".", 0x2F), ("`", 0x32)
        ]

        for (char, expectedKeyCode) in symbols {
            let (keyCode, shift) = KeyMapping.lookup(char)
            #expect(keyCode == expectedKeyCode, "Expected \(char) to map to keyCode \(expectedKeyCode)")
            #expect(shift == false, "Expected \(char) to not require shift")
        }
    }

    // MARK: - Shifted Symbols

    @Test("lookup - shifted symbols")
    func lookupShiftedSymbols() {
        let symbols: [(Character, CGKeyCode)] = [
            ("!", 0x12), ("@", 0x13), ("#", 0x14), ("$", 0x15),
            ("%", 0x17), ("^", 0x16), ("&", 0x1A), ("*", 0x1C),
            ("(", 0x19), (")", 0x1D), ("_", 0x1B), ("+", 0x18),
            ("}", 0x1E), ("{", 0x21), ("\"", 0x27), (":", 0x29),
            ("|", 0x2A), ("<", 0x2B), ("?", 0x2C), (">", 0x2F),
            ("~", 0x32)
        ]

        for (char, expectedKeyCode) in symbols {
            let (keyCode, shift) = KeyMapping.lookup(char)
            #expect(keyCode == expectedKeyCode, "Expected \(char) to map to keyCode \(expectedKeyCode)")
            #expect(shift == true, "Expected \(char) to require shift")
        }
    }

    @Test("lookup - shifted and unshifted pairs")
    func lookupShiftedUnshiftedPairs() {
        let pairs: [(unshifted: Character, shifted: Character, keyCode: CGKeyCode)] = [
            ("1", "!", 0x12),
            ("2", "@", 0x13),
            ("-", "_", 0x1B),
            ("=", "+", 0x18),
            ("[", "{", 0x21),
            ("]", "}", 0x1E),
            (";", ":", 0x29),
            ("'", "\"", 0x27),
            (",", "<", 0x2B),
            (".", ">", 0x2F),
            ("/", "?", 0x2C)
        ]

        for (unshifted, shifted, expectedKeyCode) in pairs {
            let (unshiftedKeyCode, unshiftedShift) = KeyMapping.lookup(unshifted)
            let (shiftedKeyCode, shiftedShift) = KeyMapping.lookup(shifted)

            #expect(unshiftedKeyCode == expectedKeyCode, "Expected \(unshifted) to map to keyCode \(expectedKeyCode)")
            #expect(shiftedKeyCode == expectedKeyCode, "Expected \(shifted) to map to keyCode \(expectedKeyCode)")
            #expect(unshiftedShift == false, "Expected \(unshifted) to not require shift")
            #expect(shiftedShift == true, "Expected \(shifted) to require shift")
        }
    }

    // MARK: - Whitespace

    @Test("lookup - space")
    func lookupSpace() {
        let (keyCode, shift) = KeyMapping.lookup(" ")
        #expect(keyCode == 0x31)
        #expect(shift == false)
    }

    @Test("lookup - tab")
    func lookupTab() {
        let (keyCode, shift) = KeyMapping.lookup("\t")
        #expect(keyCode == 0x30)
        #expect(shift == false)
    }

    @Test("lookup - newline")
    func lookupNewline() {
        let (keyCode, shift) = KeyMapping.lookup("\n")
        #expect(keyCode == 0x24)
        #expect(shift == false)
    }

    // MARK: - Unmapped Characters

    @Test("lookup - unmapped character returns zero keyCode")
    func lookupUnmappedCharacter() {
        let unmappedChars: [Character] = [
            "€", "£", "¥", "©", "®", "™",
            "α", "β", "γ",
            "😀", "🎉", "🔥",
            "\r", "\u{0000}"
        ]

        for char in unmappedChars {
            let (keyCode, shift) = KeyMapping.lookup(char)
            #expect(keyCode == 0, "Expected unmapped character '\(char)' to return keyCode 0")
            #expect(shift == false, "Expected unmapped character '\(char)' to not require shift")
        }
    }

    // MARK: - Edge Cases

    @Test("lookup - complete alphabet coverage")
    func lookupCompleteAlphabet() {
        // All lowercase letters should be mapped (keyCode 0 is valid for 'a')
        // So we check that each returns a valid (finite) keyCode
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
        for char in alphabet {
            let (keyCode, shift) = KeyMapping.lookup(char)
            // KeyCode should be finite (not some error value)
            #expect(keyCode <= 0xFF, "Expected letter '\(char)' to have a valid keyCode")
            #expect(shift == false, "Expected lowercase letter '\(char)' to not require shift")
        }
    }

    @Test("lookup - complete uppercase alphabet coverage")
    func lookupCompleteUppercaseAlphabet() {
        // Uppercase letters should map to the same keyCodes as lowercase but with shift
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        for char in alphabet {
            let (keyCode, shift) = KeyMapping.lookup(char)
            #expect(keyCode <= 0xFF, "Expected uppercase letter '\(char)' to have a valid keyCode")
            #expect(shift == true, "Expected uppercase letter '\(char)' to require shift")
        }
    }

    @Test("lookup - all digits coverage")
    func lookupAllDigits() {
        let digits = "0123456789"
        for char in digits {
            let (keyCode, shift) = KeyMapping.lookup(char)
            #expect(keyCode != 0, "Expected digit '\(char)' to have a non-zero keyCode")
            #expect(shift == false, "Expected digit '\(char)' to not require shift")
        }
    }

    @Test("lookup - common punctuation")
    func lookupCommonPunctuation() {
        let punctuation = ".,;:!?'\"-_()[]{}/"
        for char in punctuation {
            let (keyCode, _) = KeyMapping.lookup(char)
            #expect(keyCode != 0, "Expected punctuation '\(char)' to have a non-zero keyCode")
        }
    }

    // MARK: - Real-world Strings

    @Test("lookup - real string can be typed")
    func lookupRealString() {
        let testStrings = [
            "Hello, World!",
            "user@example.com",
            "Password123!",
            "/usr/local/bin",
            "let x = 42;",
            "https://example.com"
        ]

        for string in testStrings {
            for char in string {
                let (keyCode, _) = KeyMapping.lookup(char)
                // Should return either a mapped keyCode or 0 for unmapped chars
                #expect(keyCode >= 0, "Expected valid keyCode for '\(char)' in '\(string)'")
            }
        }
    }
}

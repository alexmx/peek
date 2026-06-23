import CoreGraphics

/// Maps characters to macOS virtual key codes (US keyboard layout).
/// Used by InteractionManager.type() to post correct key events.
enum KeyMapping {
    /// Returns (virtualKeyCode, needsShift) for a character.
    /// Falls back to keyCode 0 for unmapped characters (the unicode string on the event handles display).
    static func lookup(_ char: Character) -> (keyCode: CGKeyCode, shift: Bool) {
        if let mapping = table[char] {
            return mapping
        }
        // Uppercase letters
        if char.isUppercase, let lower = char.lowercased().first, let mapping = table[lower] {
            return (mapping.keyCode, true)
        }
        return (0, false)
    }

    static func keyCode(named name: String) -> CGKeyCode? {
        if let code = namedKeys[name.lowercased()] {
            return code
        }
        guard name.count == 1, let char = name.first else { return nil }
        // kVK_ANSI_A is 0x00, which collides with lookup()'s "unmapped" 0 sentinel.
        // Verify the character is actually in the table instead of testing code != 0,
        // otherwise 'a' (and chords like Cmd+A) are wrongly rejected.
        let base = char.lowercased().first ?? char
        guard table[char] != nil || table[base] != nil else { return nil }
        return lookup(char).keyCode
    }

    static var allKeyNames: [String] {
        let chars = table.keys.filter { !$0.isWhitespace && !$0.isNewline }.map(String.init)
        return (namedKeys.keys + chars).sorted()
    }

    static func parseModifiers(_ tokens: [String]) throws -> CGEventFlags {
        var flags: CGEventFlags = []
        for token in tokens {
            guard let flag = modifierMap[token.lowercased()] else {
                throw PeekError.invalidArgument(name: "modifier", value: token, valid: modifierMap.keys.sorted())
            }
            flags.insert(flag)
        }
        return flags
    }

    private static let modifierMap: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand,
        "shift": .maskShift,
        "option": .maskAlternate, "alt": .maskAlternate,
        "control": .maskControl, "ctrl": .maskControl,
        "fn": .maskSecondaryFn
    ]

    private static let namedKeys: [String: CGKeyCode] = [
        "return": 0x24, "enter": 0x24,
        "tab": 0x30,
        "space": 0x31,
        "delete": 0x33, "backspace": 0x33,
        "forwarddelete": 0x75, "fwddelete": 0x75,
        "escape": 0x35, "esc": 0x35,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        "home": 0x73, "end": 0x77,
        "pageup": 0x74, "pagedown": 0x79,
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
        "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F
    ]

    /// Virtual key codes from Carbon HIToolbox/Events.h (US keyboard layout)
    private static let table: [Character: (keyCode: CGKeyCode, shift: Bool)] = [
        // Letters (lowercase, unshifted)
        "a": (0x00, false), "s": (0x01, false), "d": (0x02, false), "f": (0x03, false),
        "h": (0x04, false), "g": (0x05, false), "z": (0x06, false), "x": (0x07, false),
        "c": (0x08, false), "v": (0x09, false), "b": (0x0B, false), "q": (0x0C, false),
        "w": (0x0D, false), "e": (0x0E, false), "r": (0x0F, false), "y": (0x10, false),
        "t": (0x11, false), "o": (0x1F, false), "u": (0x20, false), "i": (0x22, false),
        "p": (0x23, false), "l": (0x25, false), "j": (0x26, false), "k": (0x28, false),
        "n": (0x2D, false), "m": (0x2E, false),

        // Numbers (unshifted)
        "1": (0x12, false), "2": (0x13, false), "3": (0x14, false), "4": (0x15, false),
        "6": (0x16, false), "5": (0x17, false), "9": (0x19, false), "7": (0x1A, false),
        "8": (0x1C, false), "0": (0x1D, false),

        // Symbols (unshifted)
        "-": (0x1B, false), "=": (0x18, false), "]": (0x1E, false), "[": (0x21, false),
        "'": (0x27, false), ";": (0x29, false), "\\": (0x2A, false), ",": (0x2B, false),
        "/": (0x2C, false), ".": (0x2F, false), "`": (0x32, false),

        // Symbols (shifted)
        "!": (0x12, true), "@": (0x13, true), "#": (0x14, true), "$": (0x15, true),
        "^": (0x16, true), "%": (0x17, true), "(": (0x19, true), "&": (0x1A, true),
        "*": (0x1C, true), ")": (0x1D, true), "_": (0x1B, true), "+": (0x18, true),
        "}": (0x1E, true), "{": (0x21, true), "\"": (0x27, true), ":": (0x29, true),
        "|": (0x2A, true), "<": (0x2B, true), "?": (0x2C, true), ">": (0x2F, true),
        "~": (0x32, true),

        // Whitespace / control
        " ": (0x31, false), // Space
        "\t": (0x30, false), // Tab
        "\n": (0x24, false) // Return
    ]
}

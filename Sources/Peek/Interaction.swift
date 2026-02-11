import ApplicationServices
import CoreGraphics
import Foundation

enum Interaction {
    /// Click at screen coordinates.
    static func click(x: Double, y: Double) {
        let point = CGPoint(x: x, y: y)

        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)

        mouseDown?.post(tap: .cghidEventTap)
        usleep(50_000) // 50ms between down and up
        mouseUp?.post(tap: .cghidEventTap)
    }

    /// Type a string by posting key events for each character.
    static func type(text: String) {
        for char in text {
            let str = String(char) as CFString
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)

            keyDown?.keyboardSetUnicodeString(stringLength: 1, unicodeString: Array(str as String).map { $0.utf16.first! })
            keyUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: Array(str as String).map { $0.utf16.first! })

            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            usleep(10_000) // 10ms between keystrokes
        }
    }

    /// Perform an AX action on the first element matching the given filters.
    static func performAction(
        pid: pid_t,
        windowID: CGWindowID,
        action: String,
        role: String?,
        title: String?,
        value: String?,
        description: String?
    ) throws -> AXNode {
        guard AXIsProcessTrusted() else {
            throw PeekError.accessibilityNotTrusted
        }

        let window = try AccessibilityTree.findWindow(pid: pid, windowID: windowID)
        guard let element = findFirstElement(
            in: window,
            role: role,
            title: title,
            value: value,
            description: description,
            depth: 0
        ) else {
            throw PeekError.elementNotFound
        }

        let result = AXUIElementPerformAction(element.ref, action as CFString)
        // SwiftUI apps often return errors even when the action succeeds,
        // because the element gets recreated during the state change.
        // Only fail on truly fatal errors.
        let toleratedErrors: Set<AXError> = [.cannotComplete, .attributeUnsupported, .invalidUIElement]
        if result != .success && !toleratedErrors.contains(result) {
            throw PeekError.actionFailed(action, result)
        }

        return element.node
    }

    private struct ElementMatch {
        let ref: AXUIElement
        let node: AXNode
    }

    private static func findFirstElement(
        in element: AXUIElement,
        role: String?,
        title: String?,
        value: String?,
        description: String?,
        depth: Int
    ) -> ElementMatch? {
        guard depth < 50 else { return nil }

        let currentRole = axAttribute(of: element, key: kAXRoleAttribute)
        let currentTitle = axAttribute(of: element, key: kAXTitleAttribute)
        let currentValue = axAttribute(of: element, key: kAXValueAttribute)
        let currentDesc = axAttribute(of: element, key: kAXDescriptionAttribute)

        var matches = true
        if let role, currentRole != role { matches = false }
        if let title, currentTitle?.localizedCaseInsensitiveContains(title) != true { matches = false }
        if let value, currentValue?.localizedCaseInsensitiveContains(value) != true { matches = false }
        if let description, currentDesc?.localizedCaseInsensitiveContains(description) != true { matches = false }

        if matches {
            let frame = axFrame(of: element)
            let node = AXNode(
                role: currentRole ?? "unknown",
                title: currentTitle,
                value: currentValue,
                description: currentDesc,
                frame: frame.map { AXNode.FrameInfo(
                    x: Int($0.origin.x),
                    y: Int($0.origin.y),
                    width: Int($0.size.width),
                    height: Int($0.size.height)
                )},
                children: []
            )
            return ElementMatch(ref: element, node: node)
        }

        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        if result == .success, let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let found = findFirstElement(
                    in: child,
                    role: role,
                    title: title,
                    value: value,
                    description: description,
                    depth: depth + 1
                ) {
                    return found
                }
            }
        }

        return nil
    }

    private static func axAttribute(of element: AXUIElement, key: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &ref) == .success,
              let value = ref else { return nil }
        if let str = value as? String { return str }
        if let num = value as? NSNumber { return num.stringValue }
        return nil
    }

    private static func axFrame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              CFGetTypeID(posRef!) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef!) == AXValueGetTypeID()
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }

        return CGRect(origin: point, size: size)
    }
}

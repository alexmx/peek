import ApplicationServices
import Foundation

enum AccessibilityTree {
    private static let maxDepth = 50

    static func inspect(pid: pid_t, windowID: CGWindowID) throws {
        guard AXIsProcessTrusted() else {
            throw PeekError.accessibilityNotTrusted
        }

        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            throw PeekError.noWindows
        }

        // Match by CGWindowID using the private API
        let window = windows.first { win in
            var id: CGWindowID = 0
            return _AXUIElementGetWindow(win, &id) == .success && id == windowID
        } ?? windows[0]

        printElement(window, depth: 0)
    }

    private static func printElement(_ element: AXUIElement, depth: Int) {
        guard depth < maxDepth else { return }

        let indent = String(repeating: "  ", count: depth)
        let role = attribute(of: element, key: kAXRoleAttribute) ?? "unknown"
        let title = attribute(of: element, key: kAXTitleAttribute)
        let value = attribute(of: element, key: kAXValueAttribute)
        let description = attribute(of: element, key: kAXDescriptionAttribute)

        var line = "\(indent)\(role)"
        if let title, !title.isEmpty { line += "  \"\(title)\"" }
        if let value, !value.isEmpty { line += "  value=\"\(value)\"" }
        if let description, !description.isEmpty { line += "  desc=\"\(description)\"" }

        if let frame = frame(of: element) {
            line += "  (\(Int(frame.origin.x)), \(Int(frame.origin.y))) \(Int(frame.size.width))x\(Int(frame.size.height))"
        }

        print(line)

        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        if result == .success, let children = childrenRef as? [AXUIElement] {
            for child in children {
                printElement(child, depth: depth + 1)
            }
        }
    }

    private static func attribute(of element: AXUIElement, key: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &ref) == .success,
              let value = ref else { return nil }

        if let str = value as? String { return str }
        if let num = value as? NSNumber { return num.stringValue }
        return nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
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

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

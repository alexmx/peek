import ApplicationServices
import Foundation

struct AXNode: Encodable {
    let role: String
    let title: String?
    let value: String?
    let description: String?
    let frame: FrameInfo?
    let children: [AXNode]

    struct FrameInfo: Encodable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }
}

enum AccessibilityTree {
    private static let maxDepth = 50

    static func inspect(pid: pid_t, windowID: CGWindowID, json: Bool) throws {
        let window = try findWindow(pid: pid, windowID: windowID)
        let tree = buildNode(from: window, depth: 0)

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(tree)
            print(String(data: data, encoding: .utf8)!)
        } else {
            printNode(tree, depth: 0)
        }
    }

    static func findWindow(pid: pid_t, windowID: CGWindowID) throws -> AXUIElement {
        guard AXIsProcessTrusted() else {
            throw PeekError.accessibilityNotTrusted
        }

        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            throw PeekError.noWindows
        }

        return windows.first { win in
            var id: CGWindowID = 0
            return _AXUIElementGetWindow(win, &id) == .success && id == windowID
        } ?? windows[0]
    }

    private static func buildNode(from element: AXUIElement, depth: Int) -> AXNode {
        let role = attribute(of: element, key: kAXRoleAttribute) ?? "unknown"
        let title = attribute(of: element, key: kAXTitleAttribute)
        let value = attribute(of: element, key: kAXValueAttribute)
        let description = attribute(of: element, key: kAXDescriptionAttribute)

        let frameInfo: AXNode.FrameInfo? = frame(of: element).map {
            AXNode.FrameInfo(
                x: Int($0.origin.x),
                y: Int($0.origin.y),
                width: Int($0.size.width),
                height: Int($0.size.height)
            )
        }

        var childNodes: [AXNode] = []
        if depth < maxDepth {
            var childrenRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
            if result == .success, let children = childrenRef as? [AXUIElement] {
                childNodes = children.map { buildNode(from: $0, depth: depth + 1) }
            }
        }

        return AXNode(
            role: role,
            title: title,
            value: value,
            description: description,
            frame: frameInfo,
            children: childNodes
        )
    }

    private static func printNode(_ node: AXNode, depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        var line = "\(indent)\(node.role)"
        if let title = node.title, !title.isEmpty { line += "  \"\(title)\"" }
        if let value = node.value, !value.isEmpty { line += "  value=\"\(value)\"" }
        if let desc = node.description, !desc.isEmpty { line += "  desc=\"\(desc)\"" }
        if let f = node.frame {
            line += "  (\(f.x), \(f.y)) \(f.width)x\(f.height)"
        }
        print(line)

        for child in node.children {
            printNode(child, depth: depth + 1)
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

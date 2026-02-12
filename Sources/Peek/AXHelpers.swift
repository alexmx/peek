import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - AXUIElement attribute helpers

func axString(of element: AXUIElement, key: String) -> String? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &ref) == .success,
          let value = ref else { return nil }
    if let str = value as? String { return str }
    if let num = value as? NSNumber { return num.stringValue }
    return nil
}

func axBool(of element: AXUIElement, key: String) -> Bool? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &ref) == .success,
          let value = ref else { return nil }
    if let num = value as? NSNumber { return num.boolValue }
    return nil
}

func axChildren(of element: AXUIElement) -> [AXUIElement]? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
          let children = ref as? [AXUIElement] else { return nil }
    return children
}

func axFrame(of element: AXUIElement) -> CGRect? {
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

func axFrameInfo(of element: AXUIElement) -> AXNode.FrameInfo? {
    axFrame(of: element).map {
        AXNode.FrameInfo(
            x: Int($0.origin.x),
            y: Int($0.origin.y),
            width: Int($0.size.width),
            height: Int($0.size.height)
        )
    }
}

// MARK: - JSON output

func printJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    print(String(data: data, encoding: .utf8)!)
}

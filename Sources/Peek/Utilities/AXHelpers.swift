import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Role helpers

/// Strip the "AX" prefix from a role name for display (e.g. "AXButton" → "Button").
func stripAXPrefix(_ role: String) -> String {
    role.hasPrefix("AX") ? String(role.dropFirst(2)) : role
}

/// Ensure a role has the "AX" prefix for AX API comparison (e.g. "Button" → "AXButton").
func ensureAXPrefix(_ role: String) -> String {
    role.hasPrefix("AX") ? role : "AX\(role)"
}

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

/// AX errors tolerated when performing actions — SwiftUI apps often return these
/// even when the action succeeds because the element gets recreated during state changes.
let toleratedActionErrors: Set<AXError> = [.cannotComplete, .attributeUnsupported, .invalidUIElement]

extension AXError {
    var label: String {
        switch self {
        case .success: "success"
        case .failure: "general failure"
        case .illegalArgument: "illegal argument"
        case .invalidUIElement: "invalid UI element"
        case .invalidUIElementObserver: "invalid observer"
        case .cannotComplete: "cannot complete"
        case .attributeUnsupported: "attribute unsupported"
        case .actionUnsupported: "action not supported on this element"
        case .notificationUnsupported: "notification unsupported"
        case .notImplemented: "not implemented"
        case .notificationAlreadyRegistered: "notification already registered"
        case .notificationNotRegistered: "notification not registered"
        case .apiDisabled: "accessibility API disabled"
        case .noValue: "no value"
        case .parameterizedAttributeUnsupported: "parameterized attribute unsupported"
        case .notEnoughPrecision: "not enough precision"
        @unknown default: "unknown error (\(rawValue))"
        }
    }
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

import ApplicationServices
import Foundation

enum MenuBarManager {
    private static let maxDepth = 20
    static func menuBar(pid: pid_t) throws -> MenuNode {
        let menuBar = try getMenuBar(pid: pid)
        return buildMenuNode(from: menuBar)
    }

    /// Find and press a menu item by title (case-insensitive substring match).
    static func clickMenuItem(pid: pid_t, title: String) throws -> String {
        let menuBar = try getMenuBar(pid: pid)

        guard let element = findMenuItem(in: menuBar, title: title, depth: 0) else {
            throw PeekError.menuItemNotFound(title)
        }

        let pressResult = AXUIElementPerformAction(element, kAXPressAction as CFString)
        let toleratedErrors: Set<AXError> = [.cannotComplete, .attributeUnsupported, .invalidUIElement]
        if pressResult != .success, !toleratedErrors.contains(pressResult) {
            throw PeekError.actionFailed("AXPress", pressResult)
        }

        return axString(of: element, key: kAXTitleAttribute) ?? title
    }

    private static func getMenuBar(pid: pid_t) throws -> AXUIElement {
        try PermissionManager.requireAccessibility()

        let app = AXUIElementCreateApplication(pid)
        var ref: AnyObject?
        let result = AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &ref)
        guard result == .success, let ref else {
            throw PeekError.noMenuBar(pid)
        }
        // swiftlint:disable:next force_cast
        return ref as! AXUIElement
    }

    private static func findMenuItem(in element: AXUIElement, title: String, depth: Int) -> AXUIElement? {
        guard depth < maxDepth else { return nil }

        let role = axString(of: element, key: kAXRoleAttribute) ?? ""
        let itemTitle = axString(of: element, key: kAXTitleAttribute) ?? ""

        if role == "AXMenuItem", !itemTitle.isEmpty,
           itemTitle.localizedCaseInsensitiveContains(title),
           axBool(of: element, key: kAXEnabledAttribute) != false {
            return element
        }

        if let children = axChildren(of: element) {
            for child in children {
                if let found = findMenuItem(in: child, title: title, depth: depth + 1) {
                    return found
                }
            }
        }

        return nil
    }

    private static func buildMenuNode(from element: AXUIElement, depth: Int = 0) -> MenuNode {
        guard depth < maxDepth else {
            return MenuNode(title: "", role: "unknown", enabled: false, shortcut: nil, children: [])
        }

        let role = stripAXPrefix(axString(of: element, key: kAXRoleAttribute) ?? "unknown")
        let title = axString(of: element, key: kAXTitleAttribute) ?? ""
        let enabled = axBool(of: element, key: kAXEnabledAttribute) ?? true
        let shortcut = menuShortcut(of: element)

        var childNodes: [MenuNode] = []
        if let children = axChildren(of: element) {
            childNodes = children.map { buildMenuNode(from: $0, depth: depth + 1) }
        }

        return MenuNode(title: title, role: role, enabled: enabled, shortcut: shortcut, children: childNodes)
    }

    private static func menuShortcut(of element: AXUIElement) -> String? {
        var cmdCharRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuItemCmdCharAttribute as CFString, &cmdCharRef) == .success,
              let cmdChar = cmdCharRef as? String, !cmdChar.isEmpty
        else {
            return nil
        }

        var modRef: CFTypeRef?
        var mods = 0
        if AXUIElementCopyAttributeValue(element, kAXMenuItemCmdModifiersAttribute as CFString, &modRef) == .success,
           let modNum = modRef as? NSNumber
        {
            mods = modNum.intValue
        }

        var result = ""
        if mods & (1 << 2) != 0 { result += "⌃" }
        if mods & (1 << 1) != 0 { result += "⌥" }
        if mods & (1 << 0) != 0 { result += "⇧" }
        if mods & (1 << 3) == 0 { result += "⌘" } // No command modifier flag
        result += cmdChar

        return result
    }
}

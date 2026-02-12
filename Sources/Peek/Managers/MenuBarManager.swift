import ApplicationServices
import Foundation

enum MenuBarManager {
    static func menuBar(pid: pid_t) throws -> MenuNode {
        try PermissionManager.requireAccessibility()

        let app = AXUIElementCreateApplication(pid)

        var menuBarRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarRef)
        guard result == .success, let menuBar = menuBarRef else {
            throw PeekError.noMenuBar(pid)
        }

        return buildMenuNode(from: menuBar as! AXUIElement)
    }

    private static func buildMenuNode(from element: AXUIElement, depth: Int = 0) -> MenuNode {
        guard depth < 20 else {
            return MenuNode(title: "", role: "unknown", enabled: false, shortcut: nil, children: [])
        }

        let role = axString(of: element, key: kAXRoleAttribute) ?? "unknown"
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

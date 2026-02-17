import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Watch

enum MonitorManager {
    static func watch(pid: pid_t, windowID: CGWindowID, format: OutputFormat) throws {
        try PermissionManager.requireAccessibility()

        let appElement = AXBridge.application(pid: pid)

        let context = WatchContext(format: format)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()

        let notifications: [String] = [
            kAXValueChangedNotification,
            kAXUIElementDestroyedNotification,
            kAXTitleChangedNotification,
            kAXFocusedUIElementChangedNotification,
            kAXSelectedTextChangedNotification,
            kAXSelectedRowsChangedNotification,
            kAXLayoutChangedNotification,
            kAXCreatedNotification,
            kAXMovedNotification,
            kAXResizedNotification
        ]

        let observer = try AXBridge.createObserver(
            pid: pid,
            callback: watchCallback,
            element: appElement,
            notifications: notifications,
            context: contextPtr
        )
        AXBridge.attachToRunLoop(observer)

        if format != .json {
            print("Watching window \(windowID) (pid \(pid)) for changes... (Ctrl+C to stop)")
        }

        // Run forever until interrupted
        CFRunLoopRun()
    }
}

private class WatchContext {
    let format: OutputFormat
    init(format: OutputFormat) {
        self.format = format
    }
}

private func watchCallback(
    _: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let watchCtx = Unmanaged<WatchContext>.fromOpaque(context).takeUnretainedValue()

    let node = AXBridge.nodeFromElement(element)
    let notificationName = AXBridge.stripAXPrefix(notification as String)

    if watchCtx.format == .json {
        struct WatchEvent: Encodable {
            let timestamp: String
            let notification: String
            let role: String
            let title: String?
            let value: String?
            let description: String?
        }

        let formatter = ISO8601DateFormatter()
        let event = WatchEvent(
            timestamp: formatter.string(from: Date()),
            notification: notificationName,
            role: node.role,
            title: node.title,
            value: node.value,
            description: node.description
        )

        if let data = try? JSONEncoder().encode(event),
           let str = String(data: data, encoding: .utf8) {
            print(str)
            fflush(stdout)
        }
    } else {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var line = "[\(timestamp)] \(notificationName): \(node.role)"
        if let title = node.title, !title.isEmpty { line += " \"\(title)\"" }
        if let value = node.value, !value.isEmpty { line += " value=\"\(value)\"" }
        if let description = node.description, !description.isEmpty { line += " desc=\"\(description)\"" }
        print(line)
        fflush(stdout)
    }
}

// MARK: - Diff

extension MonitorManager {
    static func diff(pid: pid_t, windowID: CGWindowID, delay: Double) throws -> TreeDiff {
        try PermissionManager.requireAccessibility()

        let window = try AccessibilityManager.resolveWindow(pid: pid, windowID: windowID)

        let before = AccessibilityManager.buildTree(from: window)
        let beforeFlat = flattenNodes(before)

        Thread.sleep(forTimeInterval: delay)

        let after = AccessibilityManager.buildTree(from: window)
        let afterFlat = flattenNodes(after)

        return computeDiff(before: beforeFlat, after: afterFlat)
    }

    /// Compute diff between two flattened node lists.
    static func computeDiff(before: [AXNode], after: [AXNode]) -> TreeDiff {
        let beforeByID = Dictionary(grouping: before, by: { $0.identity })
        let afterByID = Dictionary(grouping: after, by: { $0.identity })

        let beforeKeys = Set(beforeByID.keys)
        let afterKeys = Set(afterByID.keys)

        let addedKeys = afterKeys.subtracting(beforeKeys)
        let removedKeys = beforeKeys.subtracting(afterKeys)
        let commonKeys = beforeKeys.intersection(afterKeys)

        let added = addedKeys.compactMap { afterByID[$0]?.first }
        let removed = removedKeys.compactMap { beforeByID[$0]?.first }

        var changed: [TreeDiff.NodeChange] = []
        for key in commonKeys {
            guard let b = beforeByID[key]?.first, let a = afterByID[key]?.first else { continue }
            if b != a {
                changed.append(TreeDiff.NodeChange(
                    identity: key,
                    role: a.role,
                    before: TreeDiff.ChangeValues(
                        title: b.title,
                        value: b.value,
                        description: b.description,
                        frame: b.frame
                    ),
                    after: TreeDiff.ChangeValues(
                        title: a.title,
                        value: a.value,
                        description: a.description,
                        frame: a.frame
                    )
                ))
            }
        }

        return TreeDiff(added: added, removed: removed, changed: changed)
    }

    /// Flatten a node tree into a list.
    static func flattenNodes(_ node: AXNode) -> [AXNode] {
        var result = [node.withoutChildren]
        for child in node.children {
            result.append(contentsOf: flattenNodes(child))
        }
        return result
    }
}

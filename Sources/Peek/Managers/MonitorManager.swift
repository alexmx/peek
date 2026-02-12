import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Watch

enum MonitorManager {
    static func watch(pid: pid_t, windowID: CGWindowID, format: OutputFormat) throws {
        guard AXIsProcessTrusted() else {
            throw PeekError.accessibilityNotTrusted
        }

        let appElement = AXUIElementCreateApplication(pid)

        var observer: AXObserver?
        let result = AXObserverCreate(pid, watchCallback, &observer)
        guard result == .success, let observer else {
            throw PeekError.actionFailed("AXObserverCreate", result)
        }

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
            kAXResizedNotification,
        ]

        for notification in notifications {
            AXObserverAddNotification(observer, appElement, notification as CFString, contextPtr)
        }

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

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

    let role = axString(of: element, key: kAXRoleAttribute) ?? "unknown"
    let title = axString(of: element, key: kAXTitleAttribute)
    let value = axString(of: element, key: kAXValueAttribute)
    let description = axString(of: element, key: kAXDescriptionAttribute)

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
            notification: notification as String,
            role: role,
            title: title,
            value: value,
            description: description
        )

        if let data = try? JSONEncoder().encode(event),
           let str = String(data: data, encoding: .utf8)
        {
            print(str)
            fflush(stdout)
        }
    } else {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var line = "[\(timestamp)] \(notification as String): \(role)"
        if let title, !title.isEmpty { line += " \"\(title)\"" }
        if let value, !value.isEmpty { line += " value=\"\(value)\"" }
        if let description, !description.isEmpty { line += " desc=\"\(description)\"" }
        print(line)
        fflush(stdout)
    }
}

// MARK: - Diff

extension MonitorManager {
    static func diff(pid: pid_t, windowID: CGWindowID, delay: Double) throws -> TreeDiff {
        guard AXIsProcessTrusted() else {
            throw PeekError.accessibilityNotTrusted
        }

        let window = try AccessibilityTreeManager.findWindow(pid: pid, windowID: windowID)

        let before = AccessibilityTreeManager.buildNode(from: window)
        let beforeFlat = flattenNodes(before)

        Thread.sleep(forTimeInterval: delay)

        let after = AccessibilityTreeManager.buildNode(from: window)
        let afterFlat = flattenNodes(after)

        let beforeByID = Dictionary(grouping: beforeFlat, by: { $0.identity })
        let afterByID = Dictionary(grouping: afterFlat, by: { $0.identity })

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
                    before: TreeDiff.ChangeValues(title: b.title, value: b.value, description: b.description, frame: b.frame),
                    after: TreeDiff.ChangeValues(title: a.title, value: a.value, description: a.description, frame: a.frame)
                ))
            }
        }

        return TreeDiff(added: added, removed: removed, changed: changed)
    }

    private static func flattenNodes(_ node: AXNode) -> [AXNode] {
        var result = [node.leaf]
        for child in node.children {
            result.append(contentsOf: flattenNodes(child))
        }
        return result
    }
}

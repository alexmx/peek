import ApplicationServices
import CoreGraphics
import Foundation

enum PeekError: LocalizedError, CustomStringConvertible {
    case windowNotFound(CGWindowID)
    case accessibilityNotTrusted
    case windowNotAccessible(CGWindowID)
    case failedToWrite(String)
    case elementNotFound
    case noTextContent
    case substringNotFound(String)
    case coordinateOffTarget(x: Int, y: Int, target: String, actual: String)
    case actionFailed(String, AXError)
    case noMenuBar(pid_t)
    case noExtrasMenuBar(pid_t)
    case menuItemNotFound(String)
    case screenCaptureNotGranted
    case screenCaptureStale
    case invalidCropRegion
    case captureFailed
    case noCapturableWindow
    case encodingFailed
    case activationFailed(pid_t, String)
    case unsupportedAction(String, supported: [String])
    case timeout(String, TimeInterval)
    case windowHidden(CGWindowID)
    case appNotFound(String)
    case launchFailed(String, String)
    case invalidArgument(name: String, value: String, valid: [String])

    var errorDescription: String? {
        switch self {
        case .windowNotFound(let id):
            "No window found with ID \(id). Run 'peek apps' to see available windows."
        case .accessibilityNotTrusted:
            "Accessibility permission not granted. Enable it in System Settings > Privacy & Security > Accessibility."
        case .windowNotAccessible(let id):
            "Window \(id) isn't reachable through accessibility — it's likely a background tab, minimized, or on another Space. Bring it to the front (select its tab, or peek_activate it), then retry."
        case .failedToWrite(let path):
            "Failed to write to \(path)"
        case .elementNotFound:
            "No matching element found."
        case .noTextContent:
            "Matched element exposes no readable text (AXNumberOfCharacters/AXStringForRange unsupported)."
        case .substringNotFound(let needle):
            "Substring '\(needle)' not found in the matched element's text (case-sensitive; whitespace comes from AX, not the rendered layout)."
        case .coordinateOffTarget(let x, let y, let target, let actual):
            "Coordinate (\(x), \(y)) is over '\(actual)', not the target '\(target)'. The target window is occluded or the coordinates are stale — re-read frames with peek_find, or pass window_id to disambiguate."
        case .actionFailed(let action, let error):
            "Action '\(action)' failed: \(error.label). Try a different action for this element role."
        case .noMenuBar(let pid):
            "No menu bar found for process \(pid)."
        case .noExtrasMenuBar(let pid):
            "No status-item (menu bar extra) menu found for process \(pid). The app may expose no NSStatusItem, or its status item uses a custom view with no accessibility — locate it visually and drive it with coordinate clicks."
        case .menuItemNotFound(let title):
            "No enabled menu item matching '\(title)' found. Items hidden via NSMenuItem.isHidden=true (e.g. Safari's per-tab ⌘1-9) are filtered out by macOS Accessibility and won't appear here — if you know the shortcut, send it directly with peek_key."
        case .screenCaptureNotGranted:
            "Screen Recording permission not granted. Enable it in System Settings > Privacy & Security > Screen Recording."
        case .screenCaptureStale:
            "Screen Recording permission appears stale: macOS reports it granted but capturing returns nothing. This commonly happens after the host app (e.g. Claude Code) updates, since macOS ties the grant to the app's code signature. Fix without a reboot: toggle the host app off/on under System Settings > Privacy & Security > Screen Recording, or run 'tccutil reset ScreenCapture' and re-grant, then restart the host app."
        case .invalidCropRegion:
            "Crop region is outside the window bounds."
        case .captureFailed:
            "Could not capture the window. It may have moved off-screen or to another Space, been minimized, or closed since it was last listed — re-check with 'peek apps' (off-screen windows show isOnScreen=false), then peek_activate and retry."
        case .noCapturableWindow:
            "The app has no standard windows to capture. If it's a menu-bar app, open its panel once, list it with 'peek apps --include-panels' (MCP: include_panels=true), and capture by explicit window ID — panels stay capturable by ID even after they dismiss."
        case .encodingFailed:
            "Failed to encode result as JSON."
        case .activationFailed(let pid, let name):
            "Failed to bring '\(name)' (pid \(pid)) to the foreground. macOS may have denied the activation request; try clicking the app's Dock icon and retrying."
        case .unsupportedAction(let action, let supported):
            if supported.isEmpty {
                "Action '\(action)' is not supported on this element. The element exposes no AX actions — pick a different element or use peek_click on its coordinates."
            } else {
                "Action '\(action)' is not supported on this element. Supported actions: \(supported.joined(separator: ", "))."
            }
        case .timeout(let op, let seconds):
            "Operation '\(op)' timed out after \(String(format: "%.1f", seconds))s. The target app may be unresponsive or the accessibility tree may be very large; try narrowing with role/title filters, lowering depth, or retrying."
        case .windowHidden(let id):
            "Window \(id) cannot be captured because it's off-screen or its app is hidden. Call peek_activate first, then retry the capture."
        case .appNotFound(let identifier):
            "Could not locate an app matching '\(identifier)'. Provide a valid bundle_id (e.g. com.apple.calculator), an exact name (e.g. 'Calculator'), or an absolute .app path."
        case .launchFailed(let name, let reason):
            "Failed to launch or terminate '\(name)': \(reason)."
        case .invalidArgument(let name, let value, let valid):
            "Invalid \(name) '\(value)'. Valid values: \(valid.joined(separator: ", "))."
        }
    }

    /// MCP renders errors with String(describing:); route it through errorDescription
    /// so clients get the full message instead of the bare case name.
    var description: String {
        errorDescription ?? "An unknown error occurred."
    }
}

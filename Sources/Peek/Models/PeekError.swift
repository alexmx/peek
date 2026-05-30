import ApplicationServices
import CoreGraphics
import Foundation

enum PeekError: LocalizedError {
    case windowNotFound(CGWindowID)
    case accessibilityNotTrusted
    case noWindows
    case failedToWrite(String)
    case elementNotFound
    case actionFailed(String, AXError)
    case noMenuBar(pid_t)
    case menuItemNotFound(String)
    case screenCaptureNotGranted
    case invalidCropRegion
    case captureFailed
    case encodingFailed
    case activationFailed(pid_t, String)
    case unsupportedAction(String, supported: [String])
    case timeout(String, TimeInterval)

    var errorDescription: String? {
        switch self {
        case .windowNotFound(let id):
            "No window found with ID \(id). Run 'peek apps' to see available windows."
        case .accessibilityNotTrusted:
            "Accessibility permission not granted. Enable it in System Settings > Privacy & Security > Accessibility."
        case .noWindows:
            "No accessible windows found for this application."
        case .failedToWrite(let path):
            "Failed to write to \(path)"
        case .elementNotFound:
            "No matching element found."
        case .actionFailed(let action, let error):
            "Action '\(action)' failed: \(error.label). Try a different action for this element role."
        case .noMenuBar(let pid):
            "No menu bar found for process \(pid)."
        case .menuItemNotFound(let title):
            "No enabled menu item matching '\(title)' found."
        case .screenCaptureNotGranted:
            "Screen Recording permission not granted. Enable it in System Settings > Privacy & Security > Screen Recording."
        case .invalidCropRegion:
            "Crop region is outside the window bounds."
        case .captureFailed:
            "Screen capture timed out. Try running 'peek doctor --prompt' to re-grant Screen Recording permission."
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
        }
    }
}

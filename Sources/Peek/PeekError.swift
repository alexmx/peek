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

    var errorDescription: String? {
        switch self {
        case .windowNotFound(let id):
            "No window found with ID \(id). Run 'peek list' to see available windows."
        case .accessibilityNotTrusted:
            "Accessibility permission not granted. Enable it in System Settings > Privacy & Security > Accessibility."
        case .noWindows:
            "No accessible windows found for this application."
        case .failedToWrite(let path):
            "Failed to write to \(path)"
        case .elementNotFound:
            "No matching element found."
        case .actionFailed(let action, let error):
            "Action '\(action)' failed with error code \(error.rawValue)."
        case .noMenuBar(let pid):
            "No menu bar found for process \(pid)."
        }
    }
}

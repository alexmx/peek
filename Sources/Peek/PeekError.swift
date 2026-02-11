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

    var errorDescription: String? {
        switch self {
        case .windowNotFound(let id):
            return "No window found with ID \(id). Run 'peek list' to see available windows."
        case .accessibilityNotTrusted:
            return "Accessibility permission not granted. Enable it in System Settings > Privacy & Security > Accessibility."
        case .noWindows:
            return "No accessible windows found for this application."
        case .failedToWrite(let path):
            return "Failed to write to \(path)"
        case .elementNotFound:
            return "No matching element found."
        case .actionFailed(let action, let error):
            return "Action '\(action)' failed with error code \(error.rawValue)."
        }
    }
}

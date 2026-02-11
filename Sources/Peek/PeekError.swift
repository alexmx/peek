import CoreGraphics
import Foundation

enum PeekError: LocalizedError {
    case windowNotFound(CGWindowID)
    case accessibilityNotTrusted
    case noWindows
    case failedToWrite(String)

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
        }
    }
}

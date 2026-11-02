import AppKit
import CoreGraphics

/// Apps that show iOS devices: Xcode's Device Hub (27+) and Simulator.app. They treat the
/// pointer as a finger, and Device Hub bridges the device's accessibility tree into its own.
enum TouchHost {
    static let bundleIDs: Set<String> = ["com.apple.dt.Devices", "com.apple.iphonesimulator"]

    static func owns(pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier.map(bundleIDs.contains) ?? false
    }

    /// Subrole of the group that holds the device screen's bridged elements in Device Hub.
    static let iOSContentSubrole = "iOSContentGroup"

    /// Maps the frames Device Hub reports for a landscape device back onto the screen.
    /// A workaround for a Device Hub bug: once Apple fixes it, detection stops matching and
    /// this does nothing, so it can be deleted when the oldest supported Xcode is fixed.
    ///
    /// Device Hub reports every element under the `iOSContentGroup` in the device's portrait
    /// space: rotated 90° and placed in a portrait-shaped rect anchored to one corner of the
    /// (correct) content group frame — top-right or bottom-left, depending on which way the
    /// device is turned. The elements that are direct children of the content group (the
    /// app's root view, a popover's dismiss region) are centred on that rect, which tells the
    /// two apart. Portrait frames are correct. Upside-down portrait frames come back rotated
    /// 180°, with nothing in the tree to detect it, so they are left alone. Verified on
    /// Xcode 27.2.
    struct FrameCorrection: Equatable {
        enum Anchor: Equatable {
            case topRight, bottomLeft
        }

        /// The content group's frame: the device screen as drawn in the Device Hub window.
        let screen: CGRect
        let anchor: Anchor

        /// Detect the rotation from the content group's frame and the reported frames of its
        /// direct children. Nil when the screen isn't landscape or the children aren't centred
        /// where a rotated report puts them — including once Device Hub reports correct frames.
        init?(screen: CGRect, childFrames: [CGRect]) {
            guard screen.width > screen.height, let first = childFrames.first else { return nil }
            let union = childFrames.dropFirst().reduce(first) { $0.union($1) }
            let shift = (screen.width - screen.height) / 2
            let dx = union.midX - screen.midX
            let dy = union.midY - screen.midY
            let tolerance: CGFloat = 2
            if abs(dx - shift) <= tolerance, abs(dy - shift) <= tolerance {
                self.anchor = .topRight
            } else if abs(dx + shift) <= tolerance, abs(dy + shift) <= tolerance {
                self.anchor = .bottomLeft
            } else {
                return nil
            }
            self.screen = screen
        }

        /// The on-screen rect for a reported one: rotate it back and swap width and height.
        func apply(_ reported: CGRect) -> CGRect {
            let s = screen
            let origin = switch anchor {
            case .topRight:
                CGPoint(x: s.minX + reported.minY - s.minY, y: s.minY + s.maxX - reported.maxX)
            case .bottomLeft:
                CGPoint(x: s.minX + s.maxY - reported.maxY, y: s.minY + reported.minX - s.minX)
            }
            return CGRect(origin: origin, size: CGSize(width: reported.height, height: reported.width))
        }
    }
}

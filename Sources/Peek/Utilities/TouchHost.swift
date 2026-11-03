import AppKit
import ApplicationServices
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
    /// device is turned. Where the content group's direct children sit relative to that rect
    /// tells the two apart (see `init`). Portrait frames are correct. Upside-down portrait
    /// frames come back rotated 180°, with nothing in the tree to detect it, so they are left
    /// alone. Verified on Xcode 27.2.
    struct FrameCorrection: Equatable {
        enum Anchor: Equatable, CaseIterable {
            case topRight, bottomLeft
        }

        /// Roles of the text elements whose shape helps detect a rotated report.
        static let textRoles: Set<String> = ["Heading", "StaticText"]

        /// The content group's frame: the device screen as drawn in the Device Hub window.
        let screen: CGRect
        let anchor: Anchor

        /// Slack for rounding in reported frames, in points.
        private static let tolerance: CGFloat = 2

        /// Detect the rotation from the content group's frame and the reported frames of its
        /// direct children, which a rotated report places in the portrait rect for its anchor:
        /// see `centredAnchor`, else `majorityAnchor` confirmed by `textStandsOnEnd`.
        /// `textFrames` is only evaluated for the second, so callers can gather it lazily.
        /// Nil when the screen isn't landscape or neither holds, including once Device Hub
        /// reports correct frames.
        init?(screen: CGRect, childFrames: [CGRect], textFrames: @autoclosure () -> [CGRect] = []) {
            guard screen.width - screen.height > 2 * Self.tolerance else { return nil }
            if let anchor = Self.centredAnchor(of: childFrames, in: screen) {
                self.anchor = anchor
            } else if let anchor = Self.majorityAnchor(of: childFrames, in: screen),
                      Self.textStandsOnEnd(textFrames()) {
                self.anchor = anchor
            } else {
                return nil
            }
            self.screen = screen
        }

        /// The anchor whose portrait rect the children are centred on horizontally: the app's
        /// root view, a split view's full-height columns, or a popover's dismiss region larger
        /// than the screen. A rotated report lays the device's height out horizontally, and
        /// screens fill the height.
        static func centredAnchor(of frames: [CGRect], in screen: CGRect) -> Anchor? {
            guard let first = frames.first else { return nil }
            let union = frames.dropFirst().reduce(first) { $0.union($1) }
            return Anchor.allCases.first { abs(union.midX - portraitRect(for: $0, in: screen).midX) <= tolerance }
        }

        /// The anchor whose portrait rect holds more than half the children, and more than the
        /// other rect: a screen with no full-height element, such as a hidden sidebar or an app
        /// in a smaller window. Not all of them, because hidden elements can sit off screen (a
        /// dismissed keyboard's keys). Correct frames whose content happens to fit one rect
        /// pass this too, so callers confirm it with `textStandsOnEnd`.
        static func majorityAnchor(of frames: [CGRect], in screen: CGRect) -> Anchor? {
            func count(insideRectFor anchor: Anchor) -> Int {
                let area = portraitRect(for: anchor, in: screen).insetBy(dx: -tolerance, dy: -tolerance)
                return frames.count { area.contains($0) }
            }
            let topRight = count(insideRectFor: .topRight)
            let bottomLeft = count(insideRectFor: .bottomLeft)
            if topRight > bottomLeft, topRight * 2 > frames.count { return .topRight }
            if bottomLeft > topRight, bottomLeft * 2 > frames.count { return .bottomLeft }
            return nil
        }

        /// Whether most line-shaped text (at least twice as long one way as the other) is
        /// taller than wide. Rotated one-line text stands on end; correct text lies flat. Text
        /// that isn't line-shaped doesn't count either way: an icon cell with a label under it
        /// is taller than wide on screen.
        static func textStandsOnEnd(_ frames: [CGRect]) -> Bool {
            let lines = frames.filter { max($0.width, $0.height) >= 2 * min($0.width, $0.height) }
            let standing = lines.count { $0.height > $0.width }
            return standing > lines.count - standing
        }

        /// The portrait-shaped rect a rotated report places the screen in for `anchor`.
        static func portraitRect(for anchor: Anchor, in screen: CGRect) -> CGRect {
            let size = CGSize(width: screen.height, height: screen.width)
            let origin = switch anchor {
            case .topRight: CGPoint(x: screen.maxX - size.width, y: screen.minY)
            case .bottomLeft: CGPoint(x: screen.minX, y: screen.maxY - size.height)
            }
            return CGRect(origin: origin, size: size)
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

extension TouchHost.FrameCorrection {
    /// The correction for the subtrees of `children` when `element` is Device Hub's iOS content
    /// group and its frames come back rotated; nil otherwise. Reads the live accessibility tree.
    static func detect(contentGroup element: AXUIElement, children: [AXUIElement]) -> Self? {
        guard AXBridge.subrole(of: element) == TouchHost.iOSContentSubrole,
              let screen = AXBridge.frame(of: element) else { return nil }
        return Self(
            screen: screen,
            childFrames: children.compactMap(AXBridge.frame(of:)),
            textFrames: textFrames(under: children)
        )
    }

    /// Most elements to visit when sampling text: enough to read the text's orientation
    /// without walking a large screen twice.
    private static let textSampleLimit = 300

    /// Frames of the text elements (headings, static text) in the subtrees of `roots`,
    /// breadth-first so the sample spans the screen, visiting up to `textSampleLimit` elements.
    private static func textFrames(under roots: [AXUIElement]) -> [CGRect] {
        var queue = roots[...]
        var frames: [CGRect] = []
        var visited = 0
        while let element = queue.popFirst(), visited < textSampleLimit {
            visited += 1
            if AXBridge.role(of: element).map(textRoles.contains) == true, let frame = AXBridge.frame(of: element) {
                frames.append(frame)
            }
            queue.append(contentsOf: AXBridge.children(of: element) ?? [])
        }
        return frames
    }
}

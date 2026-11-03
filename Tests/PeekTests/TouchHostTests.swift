import CoreGraphics
@testable import peek
import Testing

/// Frames below are what Device Hub (Xcode 27.2) reported for an iPad Pro 13" simulator,
/// checked against screenshots of the same window.
@Suite("TouchHost Tests")
struct TouchHostTests {
    typealias Correction = TouchHost.FrameCorrection

    private let landscapeScreen = CGRect(x: 485, y: 232, width: 669, height: 501)
    private let portraitScreen = CGRect(x: 579, y: 163, width: 479, height: 639)

    // MARK: - Detection

    @Test
    func rootAtTopRightDetectsTopRightAnchor() {
        let root = CGRect(x: 652, y: 232, width: 501, height: 669)
        let heading = CGRect(x: 1090, y: 241, width: 19, height: 78)
        #expect(Correction(screen: landscapeScreen, childFrames: [heading, root])?.anchor == .topRight)
    }

    @Test
    func rootAtBottomLeftDetectsBottomLeftAnchor() {
        let root = CGRect(x: 485, y: 64, width: 501, height: 669)
        #expect(Correction(screen: landscapeScreen, childFrames: [root])?.anchor == .bottomLeft)
    }

    @Test
    func popoverDismissRegionCentredOnRootDetectsAnchor() {
        let dismissRegion = CGRect(x: 150, y: -437, width: 1505, height: 2007)
        #expect(Correction(screen: landscapeScreen, childFrames: [dismissRegion])?.anchor == .topRight)
    }

    @Test
    func splitViewWithoutRootDetectsAnchorFromFullHeightSidebar() {
        // A split view exposes its sidebar and loose detail elements, no full-screen root.
        let screen = CGRect(x: 485.10, y: 232.07, width: 669.31, height: 501.85)
        let children = [
            CGRect(x: 652.42, y: 232.07, width: 501.98, height: 155.61), // sidebar column
            CGRect(x: 1123.03, y: 296.26, width: 10.21, height: 26.99), // "Fixture" heading
            CGRect(x: 1090.93, y: 397.41, width: 19.94, height: 113.79), // "Local Changes" heading
            CGRect(x: 852.83, y: 610.90, width: 43.53, height: 67.11) // placeholder label
        ]
        #expect(Correction(screen: screen, childFrames: children)?.anchor == .topRight)
    }

    /// The same split view with its sidebar hidden: only a button, the title and a label,
    /// none spanning the device's height. On-screen frames, checked against a screenshot.
    private let hiddenSidebarScreen = CGRect(x: 485.10, y: 232.07, width: 669.31, height: 501.85)
    private let showSidebarButton = CGRect(x: 491, y: 249, width: 17, height: 17)
    private let localChangesTitle = CGRect(x: 494, y: 275, width: 113, height: 19)
    private let placeholderLabel = CGRect(x: 786, y: 490, width: 67, height: 43)
    private var hiddenSidebarOnScreen: [CGRect] {
        [showSidebarButton, localChangesTitle, placeholderLabel]
    }

    /// The text among them (a heading and static text); the button isn't.
    private var hiddenSidebarTextOnScreen: [CGRect] {
        [localChangesTitle, placeholderLabel]
    }

    /// What Device Hub reports for an on-screen frame when rotated to `anchor`: the inverse
    /// of `FrameCorrection.apply`.
    private func reported(_ onScreen: CGRect, anchor: Correction.Anchor, in s: CGRect) -> CGRect {
        let size = CGSize(width: onScreen.height, height: onScreen.width)
        let origin = switch anchor {
        case .topRight:
            CGPoint(x: s.minY + s.maxX - onScreen.minY - size.width, y: onScreen.minX - s.minX + s.minY)
        case .bottomLeft:
            CGPoint(x: onScreen.minY - s.minY + s.minX, y: s.minX + s.maxY - onScreen.minX - size.height)
        }
        return CGRect(origin: origin, size: size)
    }

    @Test(arguments: Correction.Anchor.allCases)
    func screenWithoutFullHeightElementDetectsAnchorFromContainment(anchor: Correction.Anchor) throws {
        let children = hiddenSidebarOnScreen.map { reported($0, anchor: anchor, in: hiddenSidebarScreen) }
        let text = hiddenSidebarTextOnScreen.map { reported($0, anchor: anchor, in: hiddenSidebarScreen) }
        let correction = try #require(Correction(screen: hiddenSidebarScreen, childFrames: children, textFrames: text))
        #expect(correction.anchor == anchor)
        for (child, onScreen) in zip(children, hiddenSidebarOnScreen) {
            let mapped = correction.apply(child)
            #expect(abs(mapped.minX - onScreen.minX) < 0.01 && abs(mapped.minY - onScreen.minY) < 0.01)
            #expect(mapped.size == onScreen.size)
        }
    }

    @Test
    func sameScreenWithCorrectFramesNeedsNoCorrection() {
        // These fit the bottom-left portrait rect, like a rotated report would; the flat text
        // is what shows they're already on screen.
        let correction = Correction(
            screen: hiddenSidebarScreen,
            childFrames: hiddenSidebarOnScreen,
            textFrames: hiddenSidebarTextOnScreen
        )
        #expect(correction == nil)
    }

    @Test
    func offScreenChildDoesNotBlockDetection() {
        // A dismissed keyboard's keys sit off screen, outside the portrait rect.
        var children = hiddenSidebarOnScreen.map { reported($0, anchor: .topRight, in: hiddenSidebarScreen) }
        children.append(CGRect(x: 636.37, y: 233.05, width: 42.80, height: 65.16))
        let text = hiddenSidebarTextOnScreen.map { reported($0, anchor: .topRight, in: hiddenSidebarScreen) }
        #expect(Correction(screen: hiddenSidebarScreen, childFrames: children, textFrames: text)?.anchor == .topRight)
    }

    @Test
    func textStandsOnEndWhenMostLinesAreTallerThanWide() {
        let standing = CGRect(x: 0, y: 0, width: 19, height: 113)
        let flat = CGRect(x: 0, y: 0, width: 113, height: 19)
        #expect(Correction.textStandsOnEnd([standing, standing, flat]))
        #expect(!Correction.textStandsOnEnd([standing, flat]))
        #expect(!Correction.textStandsOnEnd([]))
    }

    @Test
    func iconCellsDoNotCountAsText() {
        // An icon with its label under it is taller than wide on screen, but isn't a line.
        let iconCell = CGRect(x: 0, y: 0, width: 64, height: 92)
        let flatLine = CGRect(x: 0, y: 0, width: 113, height: 19)
        #expect(!Correction.textStandsOnEnd([iconCell, iconCell, flatLine]))
    }

    @Test
    func containmentWithoutTextNeedsNoCorrection() {
        let children = hiddenSidebarOnScreen.map { reported($0, anchor: .topRight, in: hiddenSidebarScreen) }
        #expect(Correction(screen: hiddenSidebarScreen, childFrames: children) == nil)
    }

    @Test
    func childrenInsideBothPortraitRectsAreAmbiguous() {
        // A lone centred label fits either rotation, so the frames are left alone.
        #expect(Correction(screen: hiddenSidebarScreen, childFrames: [placeholderLabel]) == nil)
    }

    @Test
    func portraitScreenNeedsNoCorrection() {
        #expect(Correction(screen: portraitScreen, childFrames: [portraitScreen]) == nil)
    }

    @Test
    func landscapeChildrenAlreadyOnScreenNeedNoCorrection() {
        #expect(Correction(screen: landscapeScreen, childFrames: [landscapeScreen]) == nil)
    }

    @Test
    func noChildrenNeedsNoCorrection() {
        #expect(Correction(screen: landscapeScreen, childFrames: []) == nil)
    }

    // MARK: - Mapping

    @Test
    func topRightAnchorRotatesFrameOntoScreen() throws {
        // Reported as x 652 once truncated; the exact rect shares the screen's right edge.
        let root = CGRect(x: 653, y: 232, width: 501, height: 669)
        let correction = try #require(Correction(screen: landscapeScreen, childFrames: [root]))
        let openFolder = CGRect(x: 1061, y: 241, width: 25, height: 649)
        #expect(correction.apply(openFolder) == CGRect(x: 494, y: 300, width: 649, height: 25))
        #expect(correction.apply(root) == landscapeScreen)
    }

    @Test
    func bottomLeftAnchorRotatesFrameOntoScreen() throws {
        let root = CGRect(x: 485, y: 64, width: 501, height: 669)
        let correction = try #require(Correction(screen: landscapeScreen, childFrames: [root]))
        let openFolder = CGRect(x: 552, y: 74, width: 25, height: 649)
        #expect(correction.apply(openFolder) == CGRect(x: 495, y: 299, width: 649, height: 25))
        #expect(correction.apply(root) == landscapeScreen)
    }
}

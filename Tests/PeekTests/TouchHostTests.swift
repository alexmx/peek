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

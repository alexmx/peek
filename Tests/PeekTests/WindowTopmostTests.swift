import CoreGraphics
@testable import peek
import Testing

@Suite("isTopmostInLayer z-order logic")
struct WindowTopmostTests {
    /// Build a front-to-back window list the way an on-screen CGWindowList query returns it.
    private func windows(_ entries: [(id: CGWindowID, layer: Int)]) -> [WindowRecord] {
        entries.map { entry in
            WindowRecord(
                windowID: entry.id, pid: 1, ownerName: "", title: "",
                bounds: .zero, layer: entry.layer, isOnScreen: true, alpha: 1
            )
        }
    }

    @Test
    func normalFrontmost() {
        let list = windows([(10, 0), (11, 0), (12, 0)])
        #expect(InteractionManager.isTopmostInLayer(windowID: 10, windows: list))
    }

    @Test
    func normalOccluded() {
        let list = windows([(10, 0), (11, 0), (12, 0)])
        #expect(!InteractionManager.isTopmostInLayer(windowID: 11, windows: list))
        #expect(!InteractionManager.isTopmostInLayer(windowID: 12, windows: list))
    }

    // The regression the fix targets: a panel / MenuBarExtra window floats above layer 0.
    // The old check compared it against the front-most layer-0 window and never matched,
    // so a frontmost, focused panel looked permanently "not topmost" and stalled activation.

    @Test
    func panelFrontmost() {
        // A layer-3 panel sits in front of two layer-0 windows.
        let list = windows([(50, 3), (10, 0), (11, 0)])
        #expect(InteractionManager.isTopmostInLayer(windowID: 50, windows: list))
    }

    @Test
    func panelWithLayerZeroFirst() {
        // Defensive: even if the list ordering puts a layer-0 window before the panel,
        // the panel is still the front-most window *at layer 3*.
        let list = windows([(10, 0), (50, 3), (11, 0)])
        #expect(InteractionManager.isTopmostInLayer(windowID: 50, windows: list))
    }

    @Test
    func panelOccluded() {
        let list = windows([(51, 3), (50, 3), (10, 0)])
        #expect(!InteractionManager.isTopmostInLayer(windowID: 50, windows: list))
    }

    @Test
    func layerZeroWithPanelsPresent() {
        // The front-most layer-0 window (11) is topmost among layer-0 windows even though
        // a panel (50) floats above everything.
        let list = windows([(50, 3), (11, 0), (12, 0)])
        #expect(InteractionManager.isTopmostInLayer(windowID: 11, windows: list))
        #expect(!InteractionManager.isTopmostInLayer(windowID: 12, windows: list))
    }

    @Test
    func unknownWindow() {
        let list = windows([(10, 0), (11, 0)])
        #expect(InteractionManager.isTopmostInLayer(windowID: 999, windows: list))
    }

    @Test
    func emptyList() {
        #expect(InteractionManager.isTopmostInLayer(windowID: 10, windows: []))
    }

    @Test
    func unknownWindowIsNotTopmostWhenOnScreenRequired() {
        let list = windows([(10, 0), (11, 0)])
        #expect(!InteractionManager.isTopmostInLayer(windowID: 999, windows: list, requireOnScreen: true))
        #expect(!InteractionManager.isTopmostInLayer(windowID: 10, windows: [], requireOnScreen: true))
        #expect(InteractionManager.isTopmostInLayer(windowID: 10, windows: list, requireOnScreen: true))
    }
}

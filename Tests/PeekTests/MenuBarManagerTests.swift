import Foundation
@testable import peek
import Testing

@Suite("MenuBarManager Tests")
struct MenuBarManagerTests {
    // MARK: - pathSegments() Tests

    @Test
    func pathSegmentsSplitsAndTrims() {
        #expect(MenuBarManager.pathSegments("File > Open Recent > Clear Menu") == ["File", "Open Recent", "Clear Menu"])
        #expect(MenuBarManager.pathSegments(" Edit>Find ") == ["Edit", "Find"])
    }

    @Test
    func pathSegmentsDropsEmpty() {
        #expect(MenuBarManager.pathSegments("File > > Save >") == ["File", "Save"])
        #expect(MenuBarManager.pathSegments("").isEmpty)
        #expect(MenuBarManager.pathSegments(" > ").isEmpty)
    }

    @Test
    func pathSegmentsSingleTitle() {
        #expect(MenuBarManager.pathSegments("Clear Menu") == ["Clear Menu"])
    }

    // MARK: - clickMatch() Tests

    @Test
    func clickMatchExactIsCaseInsensitive() {
        #expect(MenuBarManager.clickMatch(label: "Close", query: "close") == .exact)
    }

    @Test
    func clickMatchSubstring() {
        #expect(MenuBarManager.clickMatch(label: "Close All", query: "close") == .substring)
    }

    @Test
    func clickMatchNone() {
        #expect(MenuBarManager.clickMatch(label: "Open", query: "Close") == nil)
        #expect(MenuBarManager.clickMatch(label: "", query: "") == nil)
    }
}

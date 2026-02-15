import Foundation
@testable import peek
import Testing

@Suite("AccessibilityTreeManager Tests")
struct AccessibilityTreeManagerTests {
    // MARK: - Test Data

    let simpleTree = AXNode(
        role: "Window",
        title: "Main",
        value: nil,
        description: nil,
        enabled: true,
        frame: AXNode.FrameInfo(x: 0, y: 0, width: 800, height: 600),
        children: [
            AXNode(
                role: "Button",
                title: "OK",
                value: nil,
                description: nil,
                enabled: true,
                frame: AXNode.FrameInfo(x: 100, y: 100, width: 80, height: 30),
                children: []
            ),
            AXNode(
                role: "Button",
                title: "Cancel",
                value: nil,
                description: nil,
                enabled: true,
                frame: AXNode.FrameInfo(x: 200, y: 100, width: 80, height: 30),
                children: []
            ),
            AXNode(
                role: "TextField",
                title: "Input",
                value: "Hello",
                description: nil,
                enabled: true,
                frame: AXNode.FrameInfo(x: 100, y: 50, width: 200, height: 25),
                children: []
            )
        ]
    )

    let nestedTree = AXNode(
        role: "Window",
        title: "App",
        value: nil,
        description: nil,
        enabled: true,
        frame: AXNode.FrameInfo(x: 0, y: 0, width: 1000, height: 800),
        children: [
            AXNode(
                role: "Group",
                title: "Toolbar",
                value: nil,
                description: nil,
                enabled: true,
                frame: AXNode.FrameInfo(x: 0, y: 0, width: 1000, height: 50),
                children: [
                    AXNode(
                        role: "Button",
                        title: "New",
                        value: nil,
                        description: "Create new",
                        enabled: true,
                        frame: AXNode.FrameInfo(x: 10, y: 10, width: 40, height: 30),
                        children: []
                    ),
                    AXNode(
                        role: "Button",
                        title: "Open",
                        value: nil,
                        description: "Open file",
                        enabled: true,
                        frame: AXNode.FrameInfo(x: 60, y: 10, width: 40, height: 30),
                        children: []
                    )
                ]
            ),
            AXNode(
                role: "Group",
                title: "Content",
                value: nil,
                description: nil,
                enabled: true,
                frame: AXNode.FrameInfo(x: 0, y: 50, width: 1000, height: 750),
                children: [
                    AXNode(
                        role: "TextField",
                        title: nil,
                        value: "Document text",
                        description: nil,
                        enabled: true,
                        frame: AXNode.FrameInfo(x: 20, y: 70, width: 960, height: 700),
                        children: []
                    )
                ]
            )
        ]
    )

    let overlappingTree = AXNode(
        role: "Window",
        title: "Overlay",
        value: nil,
        description: nil,
        enabled: true,
        frame: AXNode.FrameInfo(x: 0, y: 0, width: 500, height: 500),
        children: [
            AXNode(
                role: "Group",
                title: "Background",
                value: nil,
                description: nil,
                enabled: true,
                frame: AXNode.FrameInfo(x: 0, y: 0, width: 500, height: 500),
                children: [
                    AXNode(
                        role: "Button",
                        title: "Nested",
                        value: nil,
                        description: nil,
                        enabled: true,
                        frame: AXNode.FrameInfo(x: 100, y: 100, width: 100, height: 50),
                        children: []
                    )
                ]
            )
        ]
    )

    // MARK: - searchNode() Tests

    @Test("searchNode - find by role")
    func searchNodeByRole() {
        var results: [AXNode] = []
        AccessibilityTreeManager.searchNode(
            simpleTree,
            role: "Button",
            title: nil,
            value: nil,
            description: nil,
            results: &results
        )
        #expect(results.count == 2)
        #expect(results.contains { $0.title == "OK" })
        #expect(results.contains { $0.title == "Cancel" })
    }

    @Test("searchNode - find by title")
    func searchNodeByTitle() {
        var results: [AXNode] = []
        AccessibilityTreeManager.searchNode(
            simpleTree,
            role: nil,
            title: "OK",
            value: nil,
            description: nil,
            results: &results
        )
        #expect(results.count == 1)
        #expect(results[0].title == "OK")
        #expect(results[0].role == "Button")
    }

    @Test("searchNode - find by value")
    func searchNodeByValue() {
        var results: [AXNode] = []
        AccessibilityTreeManager.searchNode(
            simpleTree,
            role: nil,
            title: nil,
            value: "Hello",
            description: nil,
            results: &results
        )
        #expect(results.count == 1)
        #expect(results[0].role == "TextField")
        #expect(results[0].value == "Hello")
    }

    @Test("searchNode - find by description")
    func searchNodeByDescription() {
        var results: [AXNode] = []
        AccessibilityTreeManager.searchNode(
            nestedTree,
            role: nil,
            title: nil,
            value: nil,
            description: "Create",
            results: &results
        )
        #expect(results.count == 1)
        #expect(results[0].title == "New")
        #expect(results[0].description == "Create new")
    }

    @Test("searchNode - multiple filters")
    func searchNodeMultipleFilters() {
        var results: [AXNode] = []
        AccessibilityTreeManager.searchNode(
            nestedTree,
            role: "Button",
            title: "New",
            value: nil,
            description: "Create",
            results: &results
        )
        #expect(results.count == 1)
        #expect(results[0].title == "New")
    }

    @Test("searchNode - no matches")
    func searchNodeNoMatches() {
        var results: [AXNode] = []
        AccessibilityTreeManager.searchNode(
            simpleTree,
            role: "MenuItem",
            title: nil,
            value: nil,
            description: nil,
            results: &results
        )
        #expect(results.isEmpty)
    }

    @Test("searchNode - nil filters match all")
    func searchNodeNilFilters() {
        var results: [AXNode] = []
        AccessibilityTreeManager.searchNode(
            simpleTree,
            role: nil,
            title: nil,
            value: nil,
            description: nil,
            results: &results
        )
        // Should match: Window, 2 Buttons, 1 TextField = 4 nodes
        #expect(results.count == 4)
    }

    @Test("searchNode - nested tree search")
    func searchNodeNested() {
        var results: [AXNode] = []
        AccessibilityTreeManager.searchNode(
            nestedTree,
            role: "Button",
            title: nil,
            value: nil,
            description: nil,
            results: &results
        )
        #expect(results.count == 2)
        #expect(results.contains { $0.title == "New" })
        #expect(results.contains { $0.title == "Open" })
    }

    @Test("searchNode - results have no children")
    func searchNodeResultsNoChildren() {
        var results: [AXNode] = []
        AccessibilityTreeManager.searchNode(
            nestedTree,
            role: "Group",
            title: nil,
            value: nil,
            description: nil,
            results: &results
        )
        for result in results {
            #expect(result.children.isEmpty, "Search results should have no children")
        }
    }

    @Test("searchNode - case insensitive title")
    func searchNodeCaseInsensitive() {
        var results: [AXNode] = []
        AccessibilityTreeManager.searchNode(
            simpleTree,
            role: nil,
            title: "ok",
            value: nil,
            description: nil,
            results: &results
        )
        #expect(results.count == 1)
        #expect(results[0].title == "OK")
    }

    @Test("searchNode - partial title match")
    func searchNodePartialMatch() {
        var results: [AXNode] = []
        AccessibilityTreeManager.searchNode(
            simpleTree,
            role: nil,
            title: "Can",
            value: nil,
            description: nil,
            results: &results
        )
        #expect(results.count == 1)
        #expect(results[0].title == "Cancel")
    }

    @Test("searchNode - accumulates in results array")
    func searchNodeAccumulates() {
        var results: [AXNode] = [
            AXNode(role: "Existing", title: nil, value: nil, description: nil, enabled: true, frame: nil, children: [])
        ]
        AccessibilityTreeManager.searchNode(
            simpleTree,
            role: "Button",
            title: nil,
            value: nil,
            description: nil,
            results: &results
        )
        #expect(results.count == 3) // 1 existing + 2 buttons
        #expect(results[0].role == "Existing")
    }

    // MARK: - deepestNode() Tests

    @Test("deepestNode - point in window")
    func deepestNodeInWindow() {
        let result = AccessibilityTreeManager.deepestNode(in: simpleTree, x: 10, y: 10)
        #expect(result != nil)
        #expect(result?.role == "Window")
    }

    @Test("deepestNode - point in button")
    func deepestNodeInButton() {
        // Point inside OK button (100, 100, 80x30)
        let result = AccessibilityTreeManager.deepestNode(in: simpleTree, x: 120, y: 110)
        #expect(result != nil)
        #expect(result?.title == "OK")
        #expect(result?.role == "Button")
    }

    @Test("deepestNode - point in text field")
    func deepestNodeInTextField() {
        // Point inside TextField (100, 50, 200x25)
        let result = AccessibilityTreeManager.deepestNode(in: simpleTree, x: 150, y: 60)
        #expect(result != nil)
        #expect(result?.role == "TextField")
        #expect(result?.title == "Input")
    }

    @Test("deepestNode - point outside all nodes")
    func deepestNodeOutside() {
        let result = AccessibilityTreeManager.deepestNode(in: simpleTree, x: 1000, y: 1000)
        #expect(result == nil)
    }

    @Test("deepestNode - point on boundary")
    func deepestNodeOnBoundary() {
        // Exactly at (100, 100) - top-left corner of OK button
        let result = AccessibilityTreeManager.deepestNode(in: simpleTree, x: 100, y: 100)
        #expect(result != nil)
        #expect(result?.title == "OK")
    }

    @Test("deepestNode - point just outside boundary")
    func deepestNodeJustOutside() {
        // Just past the right edge of OK button (100 + 80 = 180)
        let result = AccessibilityTreeManager.deepestNode(in: simpleTree, x: 180, y: 110)
        // Should hit the window, not the button
        #expect(result != nil)
        #expect(result?.role == "Window")
    }

    @Test("deepestNode - nested element preferred")
    func deepestNodeNested() {
        // Point inside nested button (100, 100, 100x50)
        let result = AccessibilityTreeManager.deepestNode(in: overlappingTree, x: 120, y: 120)
        #expect(result != nil)
        #expect(result?.title == "Nested")
        #expect(result?.role == "Button")
    }

    @Test("deepestNode - parent when no nested match")
    func deepestNodeParentFallback() {
        // Point in Background group but not in nested button
        let result = AccessibilityTreeManager.deepestNode(in: overlappingTree, x: 50, y: 50)
        #expect(result != nil)
        #expect(result?.title == "Background")
        #expect(result?.role == "Group")
    }

    @Test("deepestNode - returns node without children")
    func deepestNodeNoChildren() throws {
        let result = AccessibilityTreeManager.deepestNode(in: simpleTree, x: 120, y: 110)
        #expect(result != nil)
        #expect(try #require(result?.children.isEmpty))
    }

    @Test("deepestNode - node without frame is skipped")
    func deepestNodeNoFrame() {
        let treeNoFrame = AXNode(
            role: "Window",
            title: "Test",
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: []
        )
        let result = AccessibilityTreeManager.deepestNode(in: treeNoFrame, x: 100, y: 100)
        #expect(result == nil)
    }

    @Test("deepestNode - deeply nested tree")
    func deepestNodeDeeplyNested() {
        // Point in the deeply nested TextField
        let result = AccessibilityTreeManager.deepestNode(in: nestedTree, x: 100, y: 200)
        #expect(result != nil)
        #expect(result?.role == "TextField")
        #expect(result?.value == "Document text")
    }

    @Test("deepestNode - prefers deepest when multiple match")
    func deepestNodePreference() {
        // Both Background group and Nested button contain (120, 120)
        // Should return the deeper one (Button)
        let result = AccessibilityTreeManager.deepestNode(in: overlappingTree, x: 120, y: 120)
        #expect(result?.role == "Button")
        #expect(result?.title == "Nested")
    }

    // MARK: - Edge Cases

    @Test("searchNode - empty tree")
    func searchNodeEmptyTree() {
        let emptyNode = AXNode(
            role: "Window",
            title: nil,
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: []
        )
        var results: [AXNode] = []
        AccessibilityTreeManager.searchNode(
            emptyNode,
            role: nil,
            title: nil,
            value: nil,
            description: nil,
            results: &results
        )
        #expect(results.count == 1) // Should match the window itself
    }

    @Test("deepestNode - single node")
    func deepestNodeSingleNode() {
        let single = AXNode(
            role: "Button",
            title: "Solo",
            value: nil,
            description: nil,
            enabled: true,
            frame: AXNode.FrameInfo(x: 0, y: 0, width: 100, height: 50),
            children: []
        )
        let result = AccessibilityTreeManager.deepestNode(in: single, x: 50, y: 25)
        #expect(result != nil)
        #expect(result?.title == "Solo")
    }

    @Test("searchNode - finds root node")
    func searchNodeRoot() {
        var results: [AXNode] = []
        AccessibilityTreeManager.searchNode(
            simpleTree,
            role: "Window",
            title: "Main",
            value: nil,
            description: nil,
            results: &results
        )
        #expect(results.count == 1)
        #expect(results[0].role == "Window")
        #expect(results[0].title == "Main")
    }
}

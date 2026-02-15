import Foundation
@testable import peek
import Testing

@Suite("MonitorManager Tests")
struct MonitorManagerTests {
    // MARK: - Test Data

    let singleNode = AXNode(
        role: "Button",
        title: "Click",
        value: nil,
        description: nil,
        enabled: true,
        frame: AXNode.FrameInfo(x: 10, y: 20, width: 100, height: 50),
        children: []
    )

    let treeWithChildren = AXNode(
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
                value: "text",
                description: nil,
                enabled: true,
                frame: AXNode.FrameInfo(x: 100, y: 50, width: 200, height: 25),
                children: []
            )
        ]
    )

    let deeplyNestedTree = AXNode(
        role: "Window",
        title: "App",
        value: nil,
        description: nil,
        enabled: true,
        frame: AXNode.FrameInfo(x: 0, y: 0, width: 1000, height: 800),
        children: [
            AXNode(
                role: "Group",
                title: "Level1",
                value: nil,
                description: nil,
                enabled: true,
                frame: nil,
                children: [
                    AXNode(
                        role: "Group",
                        title: "Level2",
                        value: nil,
                        description: nil,
                        enabled: true,
                        frame: nil,
                        children: [
                            AXNode(
                                role: "Group",
                                title: "Level3",
                                value: nil,
                                description: nil,
                                enabled: true,
                                frame: nil,
                                children: [
                                    AXNode(
                                        role: "Button",
                                        title: "Deep",
                                        value: nil,
                                        description: nil,
                                        enabled: true,
                                        frame: nil,
                                        children: []
                                    )
                                ]
                            )
                        ]
                    )
                ]
            )
        ]
    )

    let wideTree = AXNode(
        role: "Window",
        title: "Wide",
        value: nil,
        description: nil,
        enabled: true,
        frame: nil,
        children: (1...10).map { i in
            AXNode(
                role: "Button",
                title: "Button\(i)",
                value: nil,
                description: nil,
                enabled: true,
                frame: nil,
                children: []
            )
        }
    )

    // MARK: - flattenNodes() Tests

    @Test("flattenNodes - single node with no children")
    func flattenSingleNode() {
        let result = MonitorManager.flattenNodes(singleNode)
        #expect(result.count == 1)
        #expect(result[0].title == "Click")
        #expect(result[0].role == "Button")
    }

    @Test("flattenNodes - node with direct children")
    func flattenWithChildren() {
        let result = MonitorManager.flattenNodes(treeWithChildren)
        // Window + 3 children = 4 nodes
        #expect(result.count == 4)
    }

    @Test("flattenNodes - first element is root")
    func flattenRootFirst() {
        let result = MonitorManager.flattenNodes(treeWithChildren)
        #expect(result[0].role == "Window")
        #expect(result[0].title == "Main")
    }

    @Test("flattenNodes - includes all children")
    func flattenIncludesAllChildren() {
        let result = MonitorManager.flattenNodes(treeWithChildren)
        let titles = result.compactMap { $0.title }
        #expect(titles.contains("Main"))
        #expect(titles.contains("OK"))
        #expect(titles.contains("Cancel"))
        #expect(titles.contains("Input"))
    }

    @Test("flattenNodes - deeply nested tree")
    func flattenDeeplyNested() {
        let result = MonitorManager.flattenNodes(deeplyNestedTree)
        // Window + Level1 + Level2 + Level3 + Deep button = 5 nodes
        #expect(result.count == 5)

        let titles = result.compactMap { $0.title }
        #expect(titles.contains("App"))
        #expect(titles.contains("Level1"))
        #expect(titles.contains("Level2"))
        #expect(titles.contains("Level3"))
        #expect(titles.contains("Deep"))
    }

    @Test("flattenNodes - wide tree")
    func flattenWideTree() {
        let result = MonitorManager.flattenNodes(wideTree)
        // Window + 10 buttons = 11 nodes
        #expect(result.count == 11)
    }

    @Test("flattenNodes - preserves node order (depth-first)")
    func flattenPreservesOrder() {
        let tree = AXNode(
            role: "Root",
            title: "A",
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: [
                AXNode(
                    role: "Group",
                    title: "B",
                    value: nil,
                    description: nil,
                    enabled: true,
                    frame: nil,
                    children: [
                        AXNode(
                            role: "Item",
                            title: "C",
                            value: nil,
                            description: nil,
                            enabled: true,
                            frame: nil,
                            children: []
                        )
                    ]
                ),
                AXNode(
                    role: "Item",
                    title: "D",
                    value: nil,
                    description: nil,
                    enabled: true,
                    frame: nil,
                    children: []
                )
            ]
        )

        let result = MonitorManager.flattenNodes(tree)
        let titles = result.compactMap { $0.title }

        // Depth-first order: A, B, C, D
        #expect(titles == ["A", "B", "C", "D"])
    }

    @Test("flattenNodes - all nodes have no children")
    func flattenNodesHaveNoChildren() {
        let result = MonitorManager.flattenNodes(treeWithChildren)
        for node in result {
            #expect(node.children.isEmpty, "Flattened nodes should have no children")
        }
    }

    @Test("flattenNodes - preserves all properties")
    func flattenPreservesProperties() {
        let result = MonitorManager.flattenNodes(singleNode)
        let flattened = result[0]

        #expect(flattened.role == singleNode.role)
        #expect(flattened.title == singleNode.title)
        #expect(flattened.value == singleNode.value)
        #expect(flattened.description == singleNode.description)
        #expect(flattened.enabled == singleNode.enabled)
        #expect(flattened.frame == singleNode.frame)
    }

    @Test("flattenNodes - handles nil properties")
    func flattenNilProperties() {
        let nodeWithNils = AXNode(
            role: "Button",
            title: nil,
            value: nil,
            description: nil,
            enabled: nil,
            frame: nil,
            children: []
        )

        let result = MonitorManager.flattenNodes(nodeWithNils)
        #expect(result.count == 1)
        #expect(result[0].title == nil)
        #expect(result[0].value == nil)
        #expect(result[0].description == nil)
        #expect(result[0].enabled == nil)
        #expect(result[0].frame == nil)
    }

    @Test("flattenNodes - large tree performance")
    func flattenLargeTree() {
        // Create a tree with many nodes
        let largeTree = AXNode(
            role: "Window",
            title: "Root",
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: (1...50).map { i in
                AXNode(
                    role: "Group",
                    title: "Group\(i)",
                    value: nil,
                    description: nil,
                    enabled: true,
                    frame: nil,
                    children: (1...5).map { j in
                        AXNode(
                            role: "Item",
                            title: "Item\(i)-\(j)",
                            value: nil,
                            description: nil,
                            enabled: true,
                            frame: nil,
                            children: []
                        )
                    }
                )
            }
        )

        let result = MonitorManager.flattenNodes(largeTree)
        // Root + 50 groups + (50 * 5 items) = 1 + 50 + 250 = 301
        #expect(result.count == 301)
    }

    @Test("flattenNodes - balanced tree")
    func flattenBalancedTree() {
        let balanced = AXNode(
            role: "Root",
            title: "R",
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: [
                AXNode(
                    role: "Group",
                    title: "L",
                    value: nil,
                    description: nil,
                    enabled: true,
                    frame: nil,
                    children: [
                        AXNode(
                            role: "Item",
                            title: "LL",
                            value: nil,
                            description: nil,
                            enabled: true,
                            frame: nil,
                            children: []
                        ),
                        AXNode(
                            role: "Item",
                            title: "LR",
                            value: nil,
                            description: nil,
                            enabled: true,
                            frame: nil,
                            children: []
                        )
                    ]
                ),
                AXNode(
                    role: "Group",
                    title: "R",
                    value: nil,
                    description: nil,
                    enabled: true,
                    frame: nil,
                    children: [
                        AXNode(
                            role: "Item",
                            title: "RL",
                            value: nil,
                            description: nil,
                            enabled: true,
                            frame: nil,
                            children: []
                        ),
                        AXNode(
                            role: "Item",
                            title: "RR",
                            value: nil,
                            description: nil,
                            enabled: true,
                            frame: nil,
                            children: []
                        )
                    ]
                )
            ]
        )

        let result = MonitorManager.flattenNodes(balanced)
        // 1 root + 2 groups + 4 items = 7
        #expect(result.count == 7)
    }

    @Test("flattenNodes - empty children array")
    func flattenEmptyChildren() {
        let nodeEmptyChildren = AXNode(
            role: "Window",
            title: "Empty",
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: []
        )

        let result = MonitorManager.flattenNodes(nodeEmptyChildren)
        #expect(result.count == 1)
        #expect(result[0].title == "Empty")
    }

    @Test("flattenNodes - mixed depth tree")
    func flattenMixedDepth() {
        let mixed = AXNode(
            role: "Window",
            title: "Mixed",
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: [
                AXNode(
                    role: "Button",
                    title: "Shallow",
                    value: nil,
                    description: nil,
                    enabled: true,
                    frame: nil,
                    children: []
                ),
                AXNode(
                    role: "Group",
                    title: "Deep",
                    value: nil,
                    description: nil,
                    enabled: true,
                    frame: nil,
                    children: [
                        AXNode(
                            role: "Group",
                            title: "Deeper",
                            value: nil,
                            description: nil,
                            enabled: true,
                            frame: nil,
                            children: [
                                AXNode(
                                    role: "Button",
                                    title: "Deepest",
                                    value: nil,
                                    description: nil,
                                    enabled: true,
                                    frame: nil,
                                    children: []
                                )
                            ]
                        )
                    ]
                )
            ]
        )

        let result = MonitorManager.flattenNodes(mixed)
        // Window + Shallow + Deep + Deeper + Deepest = 5
        #expect(result.count == 5)

        let titles = result.compactMap { $0.title }
        #expect(titles.contains("Shallow"))
        #expect(titles.contains("Deepest"))
    }

    // MARK: - computeDiff() Tests

    @Test("computeDiff - no changes")
    func computeDiffNoChanges() {
        let nodes = [
            AXNode(role: "Window", title: "Test", value: nil, description: nil, enabled: true, frame: nil, children: [])
        ]
        let diff = MonitorManager.computeDiff(before: nodes, after: nodes)
        #expect(diff.added.isEmpty)
        #expect(diff.removed.isEmpty)
        #expect(diff.changed.isEmpty)
    }

    @Test("computeDiff - added nodes")
    func computeDiffAdded() {
        let before = [
            AXNode(role: "Window", title: "W", value: nil, description: nil, enabled: true, frame: nil, children: [])
        ]
        let after = [
            AXNode(role: "Window", title: "W", value: nil, description: nil, enabled: true, frame: nil, children: []),
            AXNode(role: "Button", title: "New", value: nil, description: nil, enabled: true, frame: nil, children: [])
        ]
        let diff = MonitorManager.computeDiff(before: before, after: after)
        #expect(diff.added.count == 1)
        #expect(diff.added[0].title == "New")
        #expect(diff.removed.isEmpty)
        #expect(diff.changed.isEmpty)
    }

    @Test("computeDiff - removed nodes")
    func computeDiffRemoved() {
        let before = [
            AXNode(role: "Window", title: "W", value: nil, description: nil, enabled: true, frame: nil, children: []),
            AXNode(role: "Button", title: "Old", value: nil, description: nil, enabled: true, frame: nil, children: [])
        ]
        let after = [
            AXNode(role: "Window", title: "W", value: nil, description: nil, enabled: true, frame: nil, children: [])
        ]
        let diff = MonitorManager.computeDiff(before: before, after: after)
        #expect(diff.added.isEmpty)
        #expect(diff.removed.count == 1)
        #expect(diff.removed[0].title == "Old")
        #expect(diff.changed.isEmpty)
    }

    @Test("computeDiff - title change creates different identity")
    func computeDiffChangedTitle() {
        // Identity includes title, so changing title = different identity = removed + added
        let before = [
            AXNode(
                role: "Button",
                title: "Old",
                value: nil,
                description: "btn",
                enabled: true,
                frame: AXNode.FrameInfo(x: 10, y: 20, width: 50, height: 30),
                children: []
            )
        ]
        let after = [
            AXNode(
                role: "Button",
                title: "New",
                value: nil,
                description: "btn",
                enabled: true,
                frame: AXNode.FrameInfo(x: 10, y: 20, width: 50, height: 30),
                children: []
            )
        ]
        let diff = MonitorManager.computeDiff(before: before, after: after)
        #expect(diff.added.count == 1)
        #expect(diff.removed.count == 1)
        #expect(diff.changed.isEmpty)
    }

    @Test("computeDiff - changed value")
    func computeDiffChangedValue() {
        let before = [
            AXNode(
                role: "TextField",
                title: "Input",
                value: "old text",
                description: nil,
                enabled: true,
                frame: AXNode.FrameInfo(x: 10, y: 20, width: 100, height: 25),
                children: []
            )
        ]
        let after = [
            AXNode(
                role: "TextField",
                title: "Input",
                value: "new text",
                description: nil,
                enabled: true,
                frame: AXNode.FrameInfo(x: 10, y: 20, width: 100, height: 25),
                children: []
            )
        ]
        let diff = MonitorManager.computeDiff(before: before, after: after)
        #expect(diff.changed.count == 1)
        #expect(diff.changed[0].before.value == "old text")
        #expect(diff.changed[0].after.value == "new text")
    }

    @Test("computeDiff - frame position change creates different identity")
    func computeDiffChangedFrame() {
        // Identity includes frame position, so moving = different identity = removed + added
        let before = [
            AXNode(
                role: "Button",
                title: "Btn",
                value: nil,
                description: nil,
                enabled: true,
                frame: AXNode.FrameInfo(x: 10, y: 20, width: 50, height: 30),
                children: []
            )
        ]
        let after = [
            AXNode(
                role: "Button",
                title: "Btn",
                value: nil,
                description: nil,
                enabled: true,
                frame: AXNode.FrameInfo(x: 100, y: 200, width: 50, height: 30),
                children: []
            )
        ]
        let diff = MonitorManager.computeDiff(before: before, after: after)
        // Position change = different identity
        #expect(diff.added.count == 1)
        #expect(diff.removed.count == 1)
        #expect(diff.changed.isEmpty)
    }

    @Test("computeDiff - complex scenario")
    func computeDiffComplex() {
        let before = [
            AXNode(role: "Window", title: "W", value: nil, description: nil, enabled: true, frame: nil, children: []),
            AXNode(
                role: "Button",
                title: "Unchanged",
                value: nil,
                description: nil,
                enabled: true,
                frame: nil,
                children: []
            ),
            AXNode(
                role: "Button",
                title: "ToRemove",
                value: nil,
                description: nil,
                enabled: true,
                frame: nil,
                children: []
            ),
            AXNode(
                role: "TextField",
                title: "Input",
                value: "old",
                description: nil,
                enabled: true,
                frame: nil,
                children: []
            )
        ]
        let after = [
            AXNode(role: "Window", title: "W", value: nil, description: nil, enabled: true, frame: nil, children: []),
            AXNode(
                role: "Button",
                title: "Unchanged",
                value: nil,
                description: nil,
                enabled: true,
                frame: nil,
                children: []
            ),
            AXNode(
                role: "Button",
                title: "NewButton",
                value: nil,
                description: nil,
                enabled: true,
                frame: nil,
                children: []
            ),
            AXNode(
                role: "TextField",
                title: "Input",
                value: "new",
                description: nil,
                enabled: true,
                frame: nil,
                children: []
            )
        ]
        let diff = MonitorManager.computeDiff(before: before, after: after)

        #expect(diff.added.count == 1)
        #expect(diff.added[0].title == "NewButton")

        #expect(diff.removed.count == 1)
        #expect(diff.removed[0].title == "ToRemove")

        #expect(diff.changed.count == 1)
        #expect(diff.changed[0].role == "TextField")
    }

    @Test("computeDiff - empty lists")
    func computeDiffEmptyLists() {
        let diff = MonitorManager.computeDiff(before: [], after: [])
        #expect(diff.added.isEmpty)
        #expect(diff.removed.isEmpty)
        #expect(diff.changed.isEmpty)
    }

    @Test("computeDiff - before empty")
    func computeDiffBeforeEmpty() {
        let after = [
            AXNode(role: "Button", title: "New", value: nil, description: nil, enabled: true, frame: nil, children: [])
        ]
        let diff = MonitorManager.computeDiff(before: [], after: after)
        #expect(diff.added.count == 1)
        #expect(diff.removed.isEmpty)
        #expect(diff.changed.isEmpty)
    }

    @Test("computeDiff - after empty")
    func computeDiffAfterEmpty() {
        let before = [
            AXNode(role: "Button", title: "Old", value: nil, description: nil, enabled: true, frame: nil, children: [])
        ]
        let diff = MonitorManager.computeDiff(before: before, after: [])
        #expect(diff.added.isEmpty)
        #expect(diff.removed.count == 1)
        #expect(diff.changed.isEmpty)
    }

    @Test("computeDiff - identity-based matching")
    func computeDiffIdentityBased() {
        // Same role and title but different positions = different identities
        let before = [
            AXNode(
                role: "Button",
                title: "Btn",
                value: nil,
                description: nil,
                enabled: true,
                frame: AXNode.FrameInfo(x: 10, y: 10, width: 50, height: 30),
                children: []
            )
        ]
        let after = [
            AXNode(
                role: "Button",
                title: "Btn",
                value: nil,
                description: nil,
                enabled: true,
                frame: AXNode.FrameInfo(x: 100, y: 100, width: 50, height: 30),
                children: []
            )
        ]
        let diff = MonitorManager.computeDiff(before: before, after: after)

        // Different positions = different identities = removed + added, not changed
        #expect(diff.added.count == 1)
        #expect(diff.removed.count == 1)
        #expect(diff.changed.isEmpty)
    }

    @Test("computeDiff - description change creates different identity")
    func computeDiffDescriptionChange() {
        // Identity includes description, so changing it creates different identity
        let before = [
            AXNode(
                role: "TextField",
                title: "Input",
                value: "text",
                description: "old desc",
                enabled: true,
                frame: AXNode.FrameInfo(x: 10, y: 20, width: 100, height: 25),
                children: []
            )
        ]
        let after = [
            AXNode(
                role: "TextField",
                title: "Input",
                value: "text",
                description: "new desc",
                enabled: true,
                frame: AXNode.FrameInfo(x: 10, y: 20, width: 100, height: 25),
                children: []
            )
        ]
        let diff = MonitorManager.computeDiff(before: before, after: after)

        // Description is part of identity
        #expect(diff.added.count == 1)
        #expect(diff.removed.count == 1)
        #expect(diff.changed.isEmpty)
    }

    @Test("computeDiff - detects frame size change")
    func computeDiffFrameSizeChange() {
        // Same identity (position unchanged) but frame size changed
        let before = [
            AXNode(
                role: "Button",
                title: "Btn",
                value: nil,
                description: nil,
                enabled: true,
                frame: AXNode.FrameInfo(x: 10, y: 20, width: 50, height: 30),
                children: []
            )
        ]
        let after = [
            AXNode(
                role: "Button",
                title: "Btn",
                value: nil,
                description: nil,
                enabled: true,
                frame: AXNode.FrameInfo(x: 10, y: 20, width: 100, height: 60),
                children: []
            )
        ]
        let diff = MonitorManager.computeDiff(before: before, after: after)

        #expect(diff.changed.count == 1)
        #expect(diff.changed[0].role == "Button")
        #expect(diff.changed[0].before.frame?.width == 50)
        #expect(diff.changed[0].after.frame?.width == 100)
    }
}

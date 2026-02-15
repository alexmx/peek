import Foundation
@testable import peek
import Testing

@Suite("AXNode Tests")
struct AXNodeTests {
    // MARK: - Test Data

    let sampleNode = AXNode(
        role: "Button",
        title: "Click Me",
        value: "pressed",
        description: "A clickable button",
        enabled: true,
        frame: AXNode.FrameInfo(x: 10, y: 20, width: 100, height: 50),
        children: []
    )

    let disabledNode = AXNode(
        role: "TextField",
        title: "Input",
        value: nil,
        description: "Text input field",
        enabled: false,
        frame: nil,
        children: []
    )

    let parentNode = AXNode(
        role: "Window",
        title: "Main Window",
        value: nil,
        description: nil,
        enabled: true,
        frame: AXNode.FrameInfo(x: 0, y: 0, width: 800, height: 600),
        children: [
            AXNode(
                role: "Button",
                title: "Submit",
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
            )
        ]
    )

    // MARK: - matches() Tests

    @Test("matches - exact role match")
    func matchesExactRole() {
        #expect(sampleNode.matches(role: "Button", title: nil, value: nil, description: nil))
        #expect(!sampleNode.matches(role: "TextField", title: nil, value: nil, description: nil))
    }

    @Test("matches - title case insensitive")
    func matchesTitleCaseInsensitive() {
        #expect(sampleNode.matches(role: nil, title: "click", value: nil, description: nil))
        #expect(sampleNode.matches(role: nil, title: "CLICK ME", value: nil, description: nil))
        #expect(sampleNode.matches(role: nil, title: "Click", value: nil, description: nil))
        #expect(!sampleNode.matches(role: nil, title: "Submit", value: nil, description: nil))
    }

    @Test("matches - title partial match")
    func matchesTitlePartial() {
        #expect(sampleNode.matches(role: nil, title: "Click", value: nil, description: nil))
        #expect(sampleNode.matches(role: nil, title: "Me", value: nil, description: nil))
        #expect(!sampleNode.matches(role: nil, title: "Submit", value: nil, description: nil))
    }

    @Test("matches - value case insensitive")
    func matchesValueCaseInsensitive() {
        #expect(sampleNode.matches(role: nil, title: nil, value: "pressed", description: nil))
        #expect(sampleNode.matches(role: nil, title: nil, value: "PRESSED", description: nil))
        #expect(sampleNode.matches(role: nil, title: nil, value: "press", description: nil))
    }

    @Test("matches - description case insensitive")
    func matchesDescriptionCaseInsensitive() {
        #expect(sampleNode.matches(role: nil, title: nil, value: nil, description: "clickable"))
        #expect(sampleNode.matches(role: nil, title: nil, value: nil, description: "BUTTON"))
        #expect(!sampleNode.matches(role: nil, title: nil, value: nil, description: "text field"))
    }

    @Test("matches - multiple filters combined")
    func matchesMultipleFilters() {
        #expect(sampleNode.matches(role: "Button", title: "Click", value: "pressed", description: "clickable"))
        #expect(!sampleNode.matches(role: "Button", title: "Submit", value: "pressed", description: "clickable"))
        #expect(!sampleNode.matches(role: "TextField", title: "Click", value: "pressed", description: "clickable"))
    }

    @Test("matches - all nil filters matches everything")
    func matchesAllNil() {
        #expect(sampleNode.matches(role: nil, title: nil, value: nil, description: nil))
        #expect(disabledNode.matches(role: nil, title: nil, value: nil, description: nil))
    }

    @Test("matches - nil value doesn't match filter")
    func matchesNilValue() {
        let nodeWithoutValue = AXNode(
            role: "Button",
            title: "Click",
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: []
        )
        #expect(!nodeWithoutValue.matches(role: nil, title: nil, value: "something", description: nil))
    }

    @Test("matches - empty title doesn't match non-empty filter")
    func matchesEmptyTitle() {
        let nodeWithEmptyTitle = AXNode(
            role: "Button",
            title: "",
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: []
        )
        #expect(!nodeWithEmptyTitle.matches(role: nil, title: "something", value: nil, description: nil))
    }

    // MARK: - formatted Tests

    @Test("formatted - full node with all properties")
    func formattedFullNode() {
        let formatted = sampleNode.formatted
        #expect(formatted.contains("Button"))
        #expect(formatted.contains("\"Click Me\""))
        #expect(formatted.contains("value=\"pressed\""))
        #expect(formatted.contains("desc=\"A clickable button\""))
        #expect(formatted.contains("(10, 20)"))
        #expect(formatted.contains("100x50"))
    }

    @Test("formatted - disabled node shows disabled marker")
    func formattedDisabledNode() {
        let formatted = disabledNode.formatted
        #expect(formatted.contains("(disabled)"))
    }

    @Test("formatted - enabled node doesn't show disabled marker")
    func formattedEnabledNode() {
        let formatted = sampleNode.formatted
        #expect(!formatted.contains("(disabled)"))
    }

    @Test("formatted - node without frame")
    func formattedNoFrame() {
        let formatted = disabledNode.formatted
        #expect(formatted.contains("TextField"))
        // Should not contain dimension patterns like "100x50"
        // Check that there's no "WIDTHxHEIGHT" pattern
        #expect(!formatted.contains(#/\d+x\d+/#))
        // Should not contain coordinate pattern like "(10, 20)"
        #expect(!formatted.contains(#/\(\d+,\s*\d+\)/#))
    }

    @Test("formatted - minimal node")
    func formattedMinimalNode() {
        let minimal = AXNode(
            role: "Unknown",
            title: nil,
            value: nil,
            description: nil,
            enabled: nil,
            frame: nil,
            children: []
        )
        let formatted = minimal.formatted
        #expect(formatted == "Unknown")
    }

    @Test("formatted - empty strings are omitted")
    func formattedEmptyStrings() {
        let node = AXNode(
            role: "Button",
            title: "",
            value: "",
            description: "",
            enabled: true,
            frame: nil,
            children: []
        )
        let formatted = node.formatted
        #expect(formatted == "Button")
        #expect(!formatted.contains("\"\""))
        #expect(!formatted.contains("value=\"\""))
        #expect(!formatted.contains("desc=\"\""))
    }

    // MARK: - identity Tests

    @Test("identity - includes role, title, description")
    func identityBasic() {
        let identity = sampleNode.identity
        #expect(identity.contains("Button"))
        #expect(identity.contains("Click Me"))
        #expect(identity.contains("A clickable button"))
    }

    @Test("identity - includes frame position when present")
    func identityWithFrame() {
        let identity = sampleNode.identity
        #expect(identity.contains("10,20"))
    }

    @Test("identity - without frame")
    func identityWithoutFrame() {
        let identity = disabledNode.identity
        #expect(!identity.contains(","))
        #expect(identity.contains("TextField"))
        #expect(identity.contains("Input"))
    }

    @Test("identity - handles nil title and description")
    func identityNilFields() {
        let node = AXNode(
            role: "Button",
            title: nil,
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: []
        )
        let identity = node.identity
        #expect(identity.contains("Button"))
        #expect(identity.contains("|")) // Separators for empty fields
    }

    @Test("identity - different nodes have different identities")
    func identityUniqueness() {
        let node1 = AXNode(
            role: "Button",
            title: "A",
            value: nil,
            description: nil,
            enabled: true,
            frame: AXNode.FrameInfo(x: 10, y: 20, width: 50, height: 30),
            children: []
        )
        let node2 = AXNode(
            role: "Button",
            title: "B",
            value: nil,
            description: nil,
            enabled: true,
            frame: AXNode.FrameInfo(x: 10, y: 20, width: 50, height: 30),
            children: []
        )
        #expect(node1.identity != node2.identity)
    }

    @Test("identity - same position different roles")
    func identitySamePositionDifferentRoles() {
        let node1 = AXNode(
            role: "Button",
            title: "Click",
            value: nil,
            description: nil,
            enabled: true,
            frame: AXNode.FrameInfo(x: 10, y: 20, width: 50, height: 30),
            children: []
        )
        let node2 = AXNode(
            role: "TextField",
            title: "Click",
            value: nil,
            description: nil,
            enabled: true,
            frame: AXNode.FrameInfo(x: 10, y: 20, width: 50, height: 30),
            children: []
        )
        #expect(node1.identity != node2.identity)
    }

    // MARK: - withoutChildren Tests

    @Test("withoutChildren - removes children")
    func withoutChildrenRemovesChildren() {
        let result = parentNode.withoutChildren
        #expect(result.children.isEmpty)
    }

    @Test("withoutChildren - preserves all other properties")
    func withoutChildrenPreservesProperties() {
        let result = parentNode.withoutChildren
        #expect(result.role == parentNode.role)
        #expect(result.title == parentNode.title)
        #expect(result.value == parentNode.value)
        #expect(result.description == parentNode.description)
        #expect(result.enabled == parentNode.enabled)
        #expect(result.frame == parentNode.frame)
    }

    @Test("withoutChildren - already no children")
    func withoutChildrenAlreadyEmpty() {
        let result = sampleNode.withoutChildren
        #expect(result.children.isEmpty)
        #expect(result == sampleNode)
    }

    // MARK: - Encodable Tests

    @Test("encode - enabled false is encoded")
    func encodeDisabledNode() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(disabledNode)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"enabled\":false"))
    }

    @Test("encode - enabled true is omitted")
    func encodeEnabledNode() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(sampleNode)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("\"enabled\""))
    }

    @Test("encode - enabled nil is omitted")
    func encodeEnabledNil() throws {
        let node = AXNode(
            role: "Button",
            title: nil,
            value: nil,
            description: nil,
            enabled: nil,
            frame: nil,
            children: []
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(node)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("\"enabled\""))
    }

    @Test("encode - includes all non-nil properties")
    func encodeFullNode() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(sampleNode)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"role\":\"Button\""))
        #expect(json.contains("\"title\":\"Click Me\""))
        #expect(json.contains("\"value\":\"pressed\""))
        #expect(json.contains("\"description\":\"A clickable button\""))
        #expect(json.contains("\"frame\""))
    }

    // MARK: - Equatable Tests

    @Test("equatable - identical nodes are equal")
    func equatableIdenticalNodes() {
        let node1 = AXNode(
            role: "Button",
            title: "Click",
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: []
        )
        let node2 = AXNode(
            role: "Button",
            title: "Click",
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: []
        )
        #expect(node1 == node2)
    }

    @Test("equatable - different roles are not equal")
    func equatableDifferentRoles() {
        let node1 = AXNode(
            role: "Button",
            title: "Click",
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: []
        )
        let node2 = AXNode(
            role: "TextField",
            title: "Click",
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: []
        )
        #expect(node1 != node2)
    }

    @Test("equatable - different children are not equal")
    func equatableDifferentChildren() {
        let child1 = AXNode(
            role: "Button",
            title: "A",
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: []
        )
        let child2 = AXNode(
            role: "Button",
            title: "B",
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: []
        )

        let parent1 = AXNode(
            role: "Window",
            title: nil,
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: [child1]
        )
        let parent2 = AXNode(
            role: "Window",
            title: nil,
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: [child2]
        )

        #expect(parent1 != parent2)
    }
}

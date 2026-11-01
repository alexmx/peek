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

    // MARK: - ElementFilter.matches() Tests

    @Test
    func matchesExactRole() {
        #expect(ElementFilter(role: "Button", title: nil, value: nil, description: nil).matches(sampleNode))
        #expect(!ElementFilter(role: "TextField", title: nil, value: nil, description: nil).matches(sampleNode))
    }

    @Test
    func matchesTitleCaseInsensitive() {
        #expect(ElementFilter(role: nil, title: "click", value: nil, description: nil).matches(sampleNode))
        #expect(ElementFilter(role: nil, title: "CLICK ME", value: nil, description: nil).matches(sampleNode))
        #expect(ElementFilter(role: nil, title: "Click", value: nil, description: nil).matches(sampleNode))
        #expect(!ElementFilter(role: nil, title: "Submit", value: nil, description: nil).matches(sampleNode))
    }

    @Test
    func matchesTitlePartial() {
        #expect(ElementFilter(role: nil, title: "Click", value: nil, description: nil).matches(sampleNode))
        #expect(ElementFilter(role: nil, title: "Me", value: nil, description: nil).matches(sampleNode))
        #expect(!ElementFilter(role: nil, title: "Submit", value: nil, description: nil).matches(sampleNode))
    }

    @Test
    func matchesValueCaseInsensitive() {
        #expect(ElementFilter(role: nil, title: nil, value: "pressed", description: nil).matches(sampleNode))
        #expect(ElementFilter(role: nil, title: nil, value: "PRESSED", description: nil).matches(sampleNode))
        #expect(ElementFilter(role: nil, title: nil, value: "press", description: nil).matches(sampleNode))
    }

    @Test
    func matchesDescriptionCaseInsensitive() {
        #expect(ElementFilter(role: nil, title: nil, value: nil, description: "clickable").matches(sampleNode))
        #expect(ElementFilter(role: nil, title: nil, value: nil, description: "BUTTON").matches(sampleNode))
        #expect(!ElementFilter(role: nil, title: nil, value: nil, description: "text field").matches(sampleNode))
    }

    @Test
    func matchesTitleFallsBackToDescription() {
        // Mirrors Calculator's number buttons: no AXTitle, label lives in AXDescription.
        let descOnlyNode = AXNode(
            role: "Button", title: nil, value: nil,
            description: "5", enabled: true, frame: nil, children: []
        )
        #expect(ElementFilter(role: "Button", title: "5", value: nil, description: nil).matches(descOnlyNode))
        #expect(ElementFilter(role: nil, title: "5", value: nil, description: nil).matches(descOnlyNode))
        #expect(!ElementFilter(role: nil, title: "9", value: nil, description: nil).matches(descOnlyNode))
    }

    @Test
    func matchesDescFilterRemainsStrict() {
        // A node whose label lives only in title should NOT match a desc filter.
        let titleOnlyNode = AXNode(
            role: "Button", title: "Save", value: nil,
            description: nil, enabled: true, frame: nil, children: []
        )
        #expect(ElementFilter(role: nil, title: "save", value: nil, description: nil).matches(titleOnlyNode))
        #expect(!ElementFilter(role: nil, title: nil, value: nil, description: "save").matches(titleOnlyNode))
    }

    @Test
    func matchesEnabledFilter() {
        let enabledNode = AXNode(
            role: "Button",
            title: "Go",
            value: nil,
            description: nil,
            enabled: true,
            frame: nil,
            children: []
        )
        let disabledNode = AXNode(
            role: "Button",
            title: "Stop",
            value: nil,
            description: nil,
            enabled: false,
            frame: nil,
            children: []
        )
        let implicitNode = AXNode(
            role: "Button",
            title: "X",
            value: nil,
            description: nil,
            enabled: nil,
            frame: nil,
            children: []
        )
        #expect(ElementFilter(role: nil, title: nil, value: nil, description: nil, enabled: true).matches(enabledNode))
        #expect(!ElementFilter(role: nil, title: nil, value: nil, description: nil, enabled: false)
            .matches(enabledNode))
        #expect(ElementFilter(role: nil, title: nil, value: nil, description: nil, enabled: false)
            .matches(disabledNode))
        #expect(!ElementFilter(role: nil, title: nil, value: nil, description: nil, enabled: true)
            .matches(disabledNode))
        // Nodes with enabled=nil are treated as enabled (sensible default — most AX
        // elements omit the attribute when they're enabled).
        #expect(ElementFilter(role: nil, title: nil, value: nil, description: nil, enabled: true).matches(implicitNode))
        #expect(!ElementFilter(role: nil, title: nil, value: nil, description: nil, enabled: false)
            .matches(implicitNode))
        // Filter omitted → both pass
        #expect(ElementFilter(role: nil, title: nil, value: nil, description: nil).matches(enabledNode))
        #expect(ElementFilter(role: nil, title: nil, value: nil, description: nil).matches(disabledNode))
    }

    @Test
    func matchesMultipleFilters() {
        #expect(ElementFilter(role: "Button", title: "Click", value: "pressed", description: "clickable")
            .matches(sampleNode))
        #expect(!ElementFilter(role: "Button", title: "Submit", value: "pressed", description: "clickable")
            .matches(sampleNode))
        #expect(!ElementFilter(role: "TextField", title: "Click", value: "pressed", description: "clickable")
            .matches(sampleNode))
    }

    @Test
    func matchesAllNil() {
        #expect(ElementFilter(role: nil, title: nil, value: nil, description: nil).matches(sampleNode))
        #expect(ElementFilter(role: nil, title: nil, value: nil, description: nil).matches(disabledNode))
    }

    @Test
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
        #expect(!ElementFilter(role: nil, title: nil, value: "something", description: nil).matches(nodeWithoutValue))
    }

    @Test
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
        #expect(!ElementFilter(role: nil, title: "something", value: nil, description: nil).matches(nodeWithEmptyTitle))
    }

    // MARK: - formatted Tests

    @Test
    func formattedFullNode() {
        let formatted = sampleNode.formatted
        #expect(formatted.contains("Button"))
        #expect(formatted.contains("\"Click Me\""))
        #expect(formatted.contains("value=\"pressed\""))
        #expect(formatted.contains("desc=\"A clickable button\""))
        #expect(formatted.contains("(10, 20)"))
        #expect(formatted.contains("100x50"))
    }

    @Test
    func formattedDisabledNode() {
        let formatted = disabledNode.formatted
        #expect(formatted.contains("(disabled)"))
    }

    @Test
    func formattedEnabledNode() {
        let formatted = sampleNode.formatted
        #expect(!formatted.contains("(disabled)"))
    }

    @Test
    func formattedNoFrame() {
        let formatted = disabledNode.formatted
        #expect(formatted.contains("TextField"))
        // Should not contain dimension patterns like "100x50"
        // Check that there's no "WIDTHxHEIGHT" pattern
        #expect(!formatted.contains(#/\d+x\d+/#))
        // Should not contain coordinate pattern like "(10, 20)"
        #expect(!formatted.contains(#/\(\d+,\s*\d+\)/#))
    }

    @Test
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

    @Test
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

    @Test
    func identityBasic() {
        let identity = sampleNode.identity
        #expect(identity.contains("Button"))
        #expect(identity.contains("Click Me"))
        #expect(identity.contains("A clickable button"))
    }

    @Test
    func identityWithFrame() {
        let identity = sampleNode.identity
        #expect(identity.contains("10,20"))
    }

    @Test
    func identityWithoutFrame() {
        let identity = disabledNode.identity
        #expect(!identity.contains(","))
        #expect(identity.contains("TextField"))
        #expect(identity.contains("Input"))
    }

    @Test
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

    @Test
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

    @Test
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

    @Test
    func withoutChildrenRemovesChildren() {
        let result = parentNode.withoutChildren
        #expect(result.children.isEmpty)
    }

    @Test
    func withoutChildrenPreservesProperties() {
        let result = parentNode.withoutChildren
        #expect(result.role == parentNode.role)
        #expect(result.title == parentNode.title)
        #expect(result.value == parentNode.value)
        #expect(result.description == parentNode.description)
        #expect(result.enabled == parentNode.enabled)
        #expect(result.frame == parentNode.frame)
    }

    @Test
    func withoutChildrenAlreadyEmpty() {
        let result = sampleNode.withoutChildren
        #expect(result.children.isEmpty)
        #expect(result == sampleNode)
    }

    // MARK: - Encodable Tests

    @Test
    func encodeDisabledNode() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(disabledNode)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"enabled\":false"))
    }

    @Test
    func encodeEnabledNode() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(sampleNode)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("\"enabled\""))
    }

    @Test
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

    @Test
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

    @Test
    func encodeTruncatedTextMarkers() throws {
        let node = AXNode(
            role: "StaticText", title: nil, value: "preview",
            description: nil, enabled: nil, frame: nil, children: [],
            valueTruncated: true, valueLength: 5000
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(node)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"valueTruncated\":true"))
        #expect(json.contains("\"valueLength\":5000"))
    }

    @Test
    func encodeOmitsTruncationMarkersWhenNotSet() throws {
        // Default nil markers (the common case) must not appear in output.
        let encoder = JSONEncoder()
        let data = try encoder.encode(sampleNode)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("valueTruncated"))
        #expect(!json.contains("valueLength"))
    }

    // MARK: - Equatable Tests

    @Test
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

    @Test
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

    @Test
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

import Foundation
@testable import peek
import Testing

@Suite("MenuNode Tests")
struct MenuNodeTests {
    // MARK: - Test Data

    let simpleMenuItem = MenuNode(
        title: "Open",
        role: "MenuItem",
        enabled: true,
        shortcut: "⌘O",
        children: []
    )

    let disabledMenuItem = MenuNode(
        title: "Undo",
        role: "MenuItem",
        enabled: false,
        shortcut: "⌘Z",
        children: []
    )

    let menuWithChildren = MenuNode(
        title: "File",
        role: "Menu",
        enabled: true,
        shortcut: nil,
        children: [
            MenuNode(title: "New", role: "MenuItem", enabled: true, shortcut: "⌘N", children: []),
            MenuNode(title: "Open", role: "MenuItem", enabled: true, shortcut: "⌘O", children: []),
            MenuNode(title: "Save", role: "MenuItem", enabled: true, shortcut: "⌘S", children: [])
        ]
    )

    let nestedMenu = MenuNode(
        title: "View",
        role: "Menu",
        enabled: true,
        shortcut: nil,
        children: [
            MenuNode(
                title: "Zoom",
                role: "MenuItem",
                enabled: true,
                shortcut: nil,
                children: [
                    MenuNode(title: "Zoom In", role: "MenuItem", enabled: true, shortcut: "⌘+", children: []),
                    MenuNode(title: "Zoom Out", role: "MenuItem", enabled: true, shortcut: "⌘-", children: [])
                ]
            )
        ]
    )

    // MARK: - withPath() Tests

    @Test("withPath - sets path")
    func withPathSetsPath() {
        let result = simpleMenuItem.withPath("File > Open")
        #expect(result.path == "File > Open")
    }

    @Test("withPath - clears children")
    func withPathClearsChildren() {
        let result = menuWithChildren.withPath("File")
        #expect(result.children.isEmpty)
    }

    @Test("withPath - preserves title")
    func withPathPreservesTitle() {
        let result = simpleMenuItem.withPath("File > Open")
        #expect(result.title == simpleMenuItem.title)
    }

    @Test("withPath - preserves role")
    func withPathPreservesRole() {
        let result = simpleMenuItem.withPath("File > Open")
        #expect(result.role == simpleMenuItem.role)
    }

    @Test("withPath - preserves enabled")
    func withPathPreservesEnabled() {
        let result = disabledMenuItem.withPath("Edit > Undo")
        #expect(result.enabled == disabledMenuItem.enabled)
        #expect(result.enabled == false)
    }

    @Test("withPath - preserves shortcut")
    func withPathPreservesShortcut() {
        let result = simpleMenuItem.withPath("File > Open")
        #expect(result.shortcut == simpleMenuItem.shortcut)
        #expect(result.shortcut == "⌘O")
    }

    @Test("withPath - handles empty path")
    func withPathEmptyPath() {
        let result = simpleMenuItem.withPath("")
        #expect(result.path == "")
        #expect(result.title == simpleMenuItem.title)
    }

    @Test("withPath - handles complex path")
    func withPathComplexPath() {
        let complexPath = "File > Open Recent > Documents > Today"
        let result = simpleMenuItem.withPath(complexPath)
        #expect(result.path == complexPath)
    }

    @Test("withPath - node without shortcut")
    func withPathNoShortcut() {
        let nodeNoShortcut = MenuNode(
            title: "Preferences",
            role: "MenuItem",
            enabled: true,
            shortcut: nil,
            children: []
        )
        let result = nodeNoShortcut.withPath("Settings > Preferences")
        #expect(result.shortcut == nil)
        #expect(result.path == "Settings > Preferences")
    }

    @Test("withPath - nested menu becomes flat")
    func withPathNestedBecomesFlat() {
        #expect(nestedMenu.children.count > 0)
        let result = nestedMenu.withPath("View")
        #expect(result.children.isEmpty)
    }

    // MARK: - Initialization Tests

    @Test("init - all properties set correctly")
    func initAllProperties() {
        let node = MenuNode(
            title: "Test",
            role: "MenuItem",
            enabled: true,
            shortcut: "⌘T",
            path: "Menu > Test",
            children: []
        )

        #expect(node.title == "Test")
        #expect(node.role == "MenuItem")
        #expect(node.enabled == true)
        #expect(node.shortcut == "⌘T")
        #expect(node.path == "Menu > Test")
        #expect(node.children.isEmpty)
    }

    @Test("init - default path is nil")
    func initDefaultPathNil() {
        let node = MenuNode(
            title: "Test",
            role: "MenuItem",
            enabled: true,
            shortcut: nil,
            children: []
        )

        #expect(node.path == nil)
    }

    @Test("init - with children")
    func initWithChildren() {
        let child1 = MenuNode(title: "A", role: "MenuItem", enabled: true, shortcut: nil, children: [])
        let child2 = MenuNode(title: "B", role: "MenuItem", enabled: true, shortcut: nil, children: [])

        let parent = MenuNode(
            title: "Parent",
            role: "Menu",
            enabled: true,
            shortcut: nil,
            children: [child1, child2]
        )

        #expect(parent.children.count == 2)
        #expect(parent.children[0].title == "A")
        #expect(parent.children[1].title == "B")
    }

    // MARK: - Encodable Tests

    @Test("encodable - simple menu item")
    func encodableSimpleMenuItem() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(simpleMenuItem)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"title\":\"Open\""))
        #expect(json.contains("\"role\":\"MenuItem\""))
        #expect(json.contains("\"enabled\":true"))
        #expect(json.contains("\"shortcut\":\"⌘O\""))
    }

    @Test("encodable - disabled menu item")
    func encodableDisabledMenuItem() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(disabledMenuItem)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"enabled\":false"))
    }

    @Test("encodable - menu with children")
    func encodableMenuWithChildren() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(menuWithChildren)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"title\":\"File\""))
        #expect(json.contains("\"children\""))
        #expect(json.contains("\"New\""))
        #expect(json.contains("\"Open\""))
        #expect(json.contains("\"Save\""))
    }

    @Test("encodable - node with path")
    func encodableWithPath() throws {
        let nodeWithPath = simpleMenuItem.withPath("File > Open")
        let encoder = JSONEncoder()
        let data = try encoder.encode(nodeWithPath)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"path\":\"File > Open\""))
    }

    @Test("encodable - node without shortcut")
    func encodableNoShortcut() throws {
        let nodeNoShortcut = MenuNode(
            title: "Item",
            role: "MenuItem",
            enabled: true,
            shortcut: nil,
            children: []
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(nodeNoShortcut)
        let json = try #require(String(data: data, encoding: .utf8))

        // Shortcut should be encoded as null or omitted
        #expect(json.contains("\"shortcut\":null") || !json.contains("\"shortcut\""))
    }

    // MARK: - Edge Cases

    @Test("empty title menu node")
    func emptyTitle() {
        let node = MenuNode(
            title: "",
            role: "MenuItem",
            enabled: true,
            shortcut: nil,
            children: []
        )

        #expect(node.title == "")
        let result = node.withPath("Test")
        #expect(result.title == "")
    }

    @Test("menu node with many children")
    func manyChildren() {
        let children = (1...100).map { i in
            MenuNode(
                title: "Item \(i)",
                role: "MenuItem",
                enabled: true,
                shortcut: nil,
                children: []
            )
        }

        let menu = MenuNode(
            title: "Menu",
            role: "Menu",
            enabled: true,
            shortcut: nil,
            children: children
        )

        #expect(menu.children.count == 100)
        let result = menu.withPath("Menu")
        #expect(result.children.isEmpty)
    }

    @Test("deeply nested menu structure")
    func deeplyNested() {
        let level3 = MenuNode(title: "L3", role: "MenuItem", enabled: true, shortcut: nil, children: [])
        let level2 = MenuNode(title: "L2", role: "Menu", enabled: true, shortcut: nil, children: [level3])
        let level1 = MenuNode(title: "L1", role: "Menu", enabled: true, shortcut: nil, children: [level2])
        let root = MenuNode(title: "Root", role: "Menu", enabled: true, shortcut: nil, children: [level1])

        #expect(root.children.count == 1)
        #expect(root.children[0].children.count == 1)
        #expect(root.children[0].children[0].children.count == 1)
    }

    @Test("special characters in menu shortcuts")
    func specialCharactersInShortcuts() {
        let shortcuts = ["⌘⇧N", "⌃⌥⌘T", "⇧⌘P", "⌘,", "⌘."]

        for shortcut in shortcuts {
            let node = MenuNode(
                title: "Test",
                role: "MenuItem",
                enabled: true,
                shortcut: shortcut,
                children: []
            )
            #expect(node.shortcut == shortcut)

            let result = node.withPath("Test")
            #expect(result.shortcut == shortcut)
        }
    }

    @Test("unicode characters in title and path")
    func unicodeCharacters() {
        let node = MenuNode(
            title: "文件 📁",
            role: "MenuItem",
            enabled: true,
            shortcut: nil,
            children: []
        )

        let result = node.withPath("菜单 > 文件 📁")
        #expect(result.title == "文件 📁")
        #expect(result.path == "菜单 > 文件 📁")
    }
}

import Foundation
@testable import peek
import Testing

@Suite("MenuBarManager Tests")
struct MenuBarManagerTests {
    // MARK: - Test Data

    let simpleMenu = MenuNode(
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
        title: "Edit",
        role: "Menu",
        enabled: true,
        shortcut: nil,
        children: [
            MenuNode(title: "Undo", role: "MenuItem", enabled: true, shortcut: "⌘Z", children: []),
            MenuNode(
                title: "Find",
                role: "MenuItem",
                enabled: true,
                shortcut: nil,
                children: [
                    MenuNode(title: "Find...", role: "MenuItem", enabled: true, shortcut: "⌘F", children: []),
                    MenuNode(title: "Find Next", role: "MenuItem", enabled: true, shortcut: "⌘G", children: []),
                    MenuNode(title: "Find Previous", role: "MenuItem", enabled: true, shortcut: "⌘⇧G", children: [])
                ]
            ),
            MenuNode(title: "Copy", role: "MenuItem", enabled: true, shortcut: "⌘C", children: [])
        ]
    )

    let menuWithDisabled = MenuNode(
        title: "View",
        role: "Menu",
        enabled: true,
        shortcut: nil,
        children: [
            MenuNode(title: "Zoom In", role: "MenuItem", enabled: true, shortcut: "⌘+", children: []),
            MenuNode(title: "Zoom Out", role: "MenuItem", enabled: false, shortcut: "⌘-", children: []),
            MenuNode(title: "Reset Zoom", role: "MenuItem", enabled: true, shortcut: "⌘0", children: [])
        ]
    )

    let complexMenu = MenuNode(
        title: "",
        role: "MenuBar",
        enabled: true,
        shortcut: nil,
        children: [
            MenuNode(
                title: "File",
                role: "Menu",
                enabled: true,
                shortcut: nil,
                children: [
                    MenuNode(title: "New File", role: "MenuItem", enabled: true, shortcut: nil, children: []),
                    MenuNode(title: "Open File", role: "MenuItem", enabled: true, shortcut: nil, children: [])
                ]
            ),
            MenuNode(
                title: "Edit",
                role: "Menu",
                enabled: true,
                shortcut: nil,
                children: [
                    MenuNode(title: "Copy", role: "MenuItem", enabled: true, shortcut: nil, children: []),
                    MenuNode(title: "Paste", role: "MenuItem", enabled: true, shortcut: nil, children: [])
                ]
            )
        ]
    )

    // MARK: - searchMenuNode() Tests

    @Test("searchMenuNode - find by exact title")
    func searchMenuNodeExactTitle() {
        var results: [MenuNode] = []
        MenuBarManager.searchMenuNode(simpleMenu, title: "Open", path: [], results: &results)
        #expect(results.count == 1)
        #expect(results[0].title == "Open")
        #expect(results[0].role == "MenuItem")
    }

    @Test("searchMenuNode - case insensitive search")
    func searchMenuNodeCaseInsensitive() {
        var results: [MenuNode] = []
        MenuBarManager.searchMenuNode(simpleMenu, title: "open", path: [], results: &results)
        #expect(results.count == 1)
        #expect(results[0].title == "Open")
    }

    @Test("searchMenuNode - partial match")
    func searchMenuNodePartialMatch() {
        var results: [MenuNode] = []
        MenuBarManager.searchMenuNode(simpleMenu, title: "Sav", path: [], results: &results)
        #expect(results.count == 1)
        #expect(results[0].title == "Save")
    }

    @Test("searchMenuNode - multiple matches")
    func searchMenuNodeMultipleMatches() {
        var results: [MenuNode] = []
        MenuBarManager.searchMenuNode(nestedMenu, title: "Find", path: [], results: &results)
        #expect(results.count == 4) // "Find" + "Find..." + "Find Next" + "Find Previous"
    }

    @Test("searchMenuNode - no matches")
    func searchMenuNodeNoMatches() {
        var results: [MenuNode] = []
        MenuBarManager.searchMenuNode(simpleMenu, title: "Delete", path: [], results: &results)
        #expect(results.isEmpty)
    }

    @Test("searchMenuNode - nested items found")
    func searchMenuNodeNested() {
        var results: [MenuNode] = []
        MenuBarManager.searchMenuNode(nestedMenu, title: "Find Next", path: [], results: &results)
        #expect(results.count == 1)
        #expect(results[0].title == "Find Next")
    }

    @Test("searchMenuNode - path building")
    func searchMenuNodePathBuilding() {
        var results: [MenuNode] = []
        MenuBarManager.searchMenuNode(simpleMenu, title: "New", path: [], results: &results)
        #expect(results.count == 1)
        #expect(results[0].path == "File > New")
    }

    @Test("searchMenuNode - nested path building")
    func searchMenuNodeNestedPath() {
        var results: [MenuNode] = []
        MenuBarManager.searchMenuNode(nestedMenu, title: "Find...", path: [], results: &results)
        #expect(results.count == 1)
        #expect(results[0].path == "Edit > Find > Find...")
    }

    @Test("searchMenuNode - with initial path")
    func searchMenuNodeInitialPath() {
        var results: [MenuNode] = []
        MenuBarManager.searchMenuNode(simpleMenu, title: "Open", path: ["App"], results: &results)
        #expect(results.count == 1)
        #expect(results[0].path == "App > File > Open")
    }

    @Test("searchMenuNode - only MenuItem role matches")
    func searchMenuNodeOnlyMenuItem() {
        var results: [MenuNode] = []
        // "Edit" is a Menu, not MenuItem, so shouldn't match even though title contains substring
        MenuBarManager.searchMenuNode(nestedMenu, title: "Edit", path: [], results: &results)
        #expect(results.isEmpty)
    }

    @Test("searchMenuNode - empty title node skipped")
    func searchMenuNodeEmptyTitle() {
        let menuWithEmpty = MenuNode(
            title: "Test",
            role: "Menu",
            enabled: true,
            shortcut: nil,
            children: [
                MenuNode(title: "", role: "MenuItem", enabled: true, shortcut: nil, children: []),
                MenuNode(title: "Valid", role: "MenuItem", enabled: true, shortcut: nil, children: [])
            ]
        )
        var results: [MenuNode] = []
        MenuBarManager.searchMenuNode(menuWithEmpty, title: "", path: [], results: &results)
        #expect(results.isEmpty) // Empty titles are skipped
    }

    @Test("searchMenuNode - accumulates results")
    func searchMenuNodeAccumulates() {
        var results: [MenuNode] = [
            MenuNode(
                title: "Existing",
                role: "MenuItem",
                enabled: true,
                shortcut: nil,
                path: "Pre-existing",
                children: []
            )
        ]
        MenuBarManager.searchMenuNode(simpleMenu, title: "New", path: [], results: &results)
        #expect(results.count == 2)
        #expect(results[0].title == "Existing")
        #expect(results[1].title == "New")
    }

    @Test("searchMenuNode - results have no children")
    func searchMenuNodeNoChildren() {
        var results: [MenuNode] = []
        MenuBarManager.searchMenuNode(nestedMenu, title: "Find", path: [], results: &results)
        for result in results {
            #expect(result.children.isEmpty)
        }
    }

    @Test("searchMenuNode - preserves properties")
    func searchMenuNodePreservesProperties() {
        var results: [MenuNode] = []
        MenuBarManager.searchMenuNode(simpleMenu, title: "New", path: [], results: &results)
        #expect(results.count == 1)
        let found = results[0]
        #expect(found.title == "New")
        #expect(found.role == "MenuItem")
        #expect(found.enabled == true)
        #expect(found.shortcut == "⌘N")
    }

    @Test("searchMenuNode - complex menu bar")
    func searchMenuNodeComplex() {
        var results: [MenuNode] = []
        MenuBarManager.searchMenuNode(complexMenu, title: "File", path: [], results: &results)
        #expect(results.count == 2) // "New File" and "Open File"
        #expect(results.contains { $0.title == "New File" })
        #expect(results.contains { $0.title == "Open File" })
    }

    @Test("searchMenuNode - paths in complex menu")
    func searchMenuNodeComplexPaths() {
        var results: [MenuNode] = []
        MenuBarManager.searchMenuNode(complexMenu, title: "Copy", path: [], results: &results)
        #expect(results.count == 1)
        #expect(results[0].path == "Edit > Copy")
    }

    @Test("searchMenuNode - empty path for root items")
    func searchMenuNodeEmptyPath() {
        let rootMenu = MenuNode(
            title: "",
            role: "MenuBar",
            enabled: true,
            shortcut: nil,
            children: [
                MenuNode(title: "Item", role: "MenuItem", enabled: true, shortcut: nil, children: [])
            ]
        )
        var results: [MenuNode] = []
        MenuBarManager.searchMenuNode(rootMenu, title: "Item", path: [], results: &results)
        #expect(results.count == 1)
        #expect(results[0].path == "Item")
    }

    @Test("searchMenuNode - disabled items still match")
    func searchMenuNodeDisabled() {
        var results: [MenuNode] = []
        MenuBarManager.searchMenuNode(menuWithDisabled, title: "Zoom Out", path: [], results: &results)
        #expect(results.count == 1)
        #expect(results[0].title == "Zoom Out")
        #expect(results[0].enabled == false)
    }

    @Test("searchMenuNode - deeply nested structure")
    func searchMenuNodeDeeplyNested() {
        let deep = MenuNode(
            title: "L1",
            role: "Menu",
            enabled: true,
            shortcut: nil,
            children: [
                MenuNode(
                    title: "L2",
                    role: "Menu",
                    enabled: true,
                    shortcut: nil,
                    children: [
                        MenuNode(
                            title: "L3",
                            role: "Menu",
                            enabled: true,
                            shortcut: nil,
                            children: [
                                MenuNode(
                                    title: "Deep Item",
                                    role: "MenuItem",
                                    enabled: true,
                                    shortcut: nil,
                                    children: []
                                )
                            ]
                        )
                    ]
                )
            ]
        )
        var results: [MenuNode] = []
        MenuBarManager.searchMenuNode(deep, title: "Deep", path: [], results: &results)
        #expect(results.count == 1)
        #expect(results[0].path == "L1 > L2 > L3 > Deep Item")
    }
}

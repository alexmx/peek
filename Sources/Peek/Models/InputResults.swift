import Foundation

// Results of the input commands, shared by the CLI (`--format json`) and the MCP tools.

struct ClickResult: Encodable {
    let x: Int
    let y: Int
    let count: Int
    let button: String
    let modifiers: [String]
    /// Press hold in ms; omitted for a normal click.
    let holdMs: Int?
}

struct DragResult: Encodable {
    let fromX: Int
    let fromY: Int
    let toX: Int
    let toY: Int
}

struct MoveResult: Encodable {
    let x: Int
    let y: Int
    let fromX: Int?
    let fromY: Int?
    let steps: Int
    let dwellMs: Int
    let cursor: InteractionManager.CursorPoint?
    let element: AXNode?
}

struct ScrollResult: Encodable {
    let x: Int
    let y: Int
    let deltaX: Int
    let deltaY: Int
    let mode: InteractionManager.ScrollMode
}

struct TypeResult: Encodable {
    let characters: Int
}

struct KeyResult: Encodable {
    let key: String
    let modifiers: [String]
    let keyCode: Int
}

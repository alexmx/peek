import ArgumentParser
import Foundation
import SwiftMCP

struct MCPServerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Start an MCP server for AI tool integration"
    )

    @Flag(help: "Print setup instructions for popular AI coding agents")
    var setup = false

    func run() async {
        if setup {
            printSetup()
            return
        }

        _ = try? await WindowManager.listWindows()

        let server = MCPServer(
            name: "peek",
            version: peekVersion,
            description: "Control any macOS app via the accessibility API. Discover with peek_launch or peek_apps; learn structure with peek_find (for labeled elements) or peek_tree (for unfamiliar UI); act with peek_action. Habits that cut tool-call counts: peek_key for shortcuts (⌘S, Esc, arrows); peek_type for character sequences; peek_action verify='diff' to act+verify in one call; peek_drag for gestures peek_click can't express. peek_find/peek_tree return SCREEN coords; peek_capture crop is WINDOW-relative (subtract window frame origin).",
            tools: PeekTools.all
        )
        await server.run()
    }

    private func printSetup() {
        print("""
        Add peek as an MCP server to your AI coding agent:
        
          Claude Code:          claude mcp add --transport stdio peek -- peek mcp
          Codex CLI:            codex mcp add peek -- peek mcp
          VS Code / Copilot:    code --add-mcp '{"name":"peek","command":"peek","args":["mcp"]}'
          Cursor:               cursor --add-mcp '{"name":"peek","command":"peek","args":["mcp"]}'
        """)
    }
}

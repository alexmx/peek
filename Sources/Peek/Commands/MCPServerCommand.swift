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

        let server = MCPServer(
            name: "peek",
            version: peekVersion,
            description: "See and control any macOS app — inspect UI elements, read accessibility trees, click buttons, type text, navigate menus, and capture screenshots. Workflow: (1) peek_apps to discover the app and its window frame, (2) peek_tree to explore the UI layout, (3) peek_action with resultTree=true to interact and verify the result in one call. Tips: Always filter peek_apps by app name when you know it. Always use depth with peek_tree to control output size. Use peek_watch only for async/delayed changes like loading spinners or build progress, never after peek_action. For peek_capture crop coordinates, tree/find return screen coordinates while capture crop uses window-relative offsets — subtract the window frame origin from peek_apps.",
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

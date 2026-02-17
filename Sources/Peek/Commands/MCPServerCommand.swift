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
            description: "See and control any macOS app — inspect UI elements, read accessibility trees, click buttons, type text, navigate menus, and capture screenshots. Workflow: peek_apps to discover apps, peek_find to explore elements (start broad with role, then narrow with title/desc), peek_action to interact.",
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

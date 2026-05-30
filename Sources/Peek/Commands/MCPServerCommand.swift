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
            description: "See and control any macOS app — inspect UI elements, read accessibility trees, click buttons, type text, navigate menus, and capture screenshots. Core workflow: peek_launch or peek_apps to discover the app, peek_find/peek_tree to learn the UI, peek_action with resultTree=true to act AND verify in one call. Three habits that cut tool-call counts: prefer peek_type for digit/character sequences (apps that accept keyboard input collapse N button presses into one call); use peek_action resultTree=true instead of follow-up peek_find/peek_tree; pre-read state with peek_find before peek_wait or peek_click so you target labels that actually exist. Coordinates: peek_find/peek_tree return SCREEN coords; peek_capture crop uses WINDOW-relative offsets (subtract window frame origin from peek_apps).",
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

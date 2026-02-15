import ArgumentParser
import Foundation
import SwiftCliMcp

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
            version: "1.0.0",
            tools: PeekTools.all
        )
        await server.run()
    }

    private func printSetup() {
        let binary = ProcessInfo.processInfo.arguments[0]
        let path = URL(fileURLWithPath: binary).standardized.path

        print("""
        Add peek as an MCP server to your AI coding agent:

        ── Claude Code ──────────────────────────────────────

          claude mcp add peek -- \(path) mcp

          Or add to .mcp.json:

          {
            "mcpServers": {
              "peek": {
                "type": "stdio",
                "command": "\(path)",
                "args": ["mcp"]
              }
            }
          }

        ── Codex CLI ────────────────────────────────────────

          codex mcp add peek -- \(path) mcp

          Or add to ~/.codex/config.toml:

          [mcp_servers.peek]
          command = "\(path)"
          args = ["mcp"]

        ── VS Code / GitHub Copilot ─────────────────────────

          Add to .vscode/mcp.json:

          {
            "servers": {
              "peek": {
                "type": "stdio",
                "command": "\(path)",
                "args": ["mcp"]
              }
            }
          }

        ── Cursor ───────────────────────────────────────────

          Add to .cursor/mcp.json:

          {
            "mcpServers": {
              "peek": {
                "command": "\(path)",
                "args": ["mcp"]
              }
            }
          }
        """)
    }
}

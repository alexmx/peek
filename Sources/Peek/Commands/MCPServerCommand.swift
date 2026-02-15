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

          Claude Code:          claude mcp add --transport stdio peek -- \(path) mcp
          Codex CLI:            codex mcp add peek -- \(path) mcp
          VS Code / Copilot:    code --add-mcp '{"name":"peek","command":"\(path)","args":["mcp"]}'
          Cursor:               cursor --add-mcp '{"name":"peek","command":"\(path)","args":["mcp"]}'
        """)
    }
}

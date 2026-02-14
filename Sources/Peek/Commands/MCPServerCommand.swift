import ArgumentParser
import SwiftCliMcp

struct MCPServerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp-server",
        abstract: "Start an MCP server for AI tool integration"
    )

    func run() async {
        let server = MCPServer(
            name: "peek",
            version: "1.0.0",
            tools: PeekTools.all
        )
        await server.run()
    }
}

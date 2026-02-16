import ArgumentParser
import Foundation
import ToonFormat

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case `default`
    case json
    case toon
}

// MARK: - Cached Encoders

private let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}()

private nonisolated(unsafe) let toonEncoder = TOONEncoder()

// MARK: - Print Functions

func printJSON(_ value: some Encodable) throws {
    let data = try jsonEncoder.encode(value)
    print(String(data: data, encoding: .utf8)!)
}

func printTOON(_ value: some Encodable) throws {
    let data = try toonEncoder.encode(value)
    print(String(data: data, encoding: .utf8)!)
}

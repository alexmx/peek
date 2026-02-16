import ArgumentParser
import Foundation
import ToonFormat

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case `default`
    case json
    case toon
}

func printJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    print(String(data: data, encoding: .utf8)!)
}

func printTOON(_ value: some Encodable) throws {
    let encoder = TOONEncoder()
    let data = try encoder.encode(value)
    print(String(data: data, encoding: .utf8)!)
}

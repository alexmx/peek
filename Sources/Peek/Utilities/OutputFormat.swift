import ArgumentParser
import Foundation
import ToonFormat

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case `default`
    case json
    case toon
}

// MARK: - Encoders

/// jsonEncoder is shared (Sendable); TOONEncoder isn't, so it's built per call below.
private let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}()

// MARK: - Print Functions

func printJSON(_ value: some Encodable) throws {
    try printUTF8(jsonEncoder.encode(value))
}

func printTOON(_ value: some Encodable) throws {
    try printUTF8(TOONEncoder().encode(value))
}

private func printUTF8(_ data: Data) {
    print(String(data: data, encoding: .utf8)!)
}

/// Encode `value` as JSON/TOON, or run `text()` for the human-readable default format.
func emit(_ value: some Encodable, as format: OutputFormat, text: () -> Void) throws {
    switch format {
    case .json: try printJSON(value)
    case .toon: try printTOON(value)
    case .default: text()
    }
}

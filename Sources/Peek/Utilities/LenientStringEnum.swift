import Foundation

/// A string enum for MCP tool arguments. Its cases appear in the tool's schema as the
/// allowed values, and decoding ignores case ("Right" → `.right`), so agents that
/// capitalize a value still get through. An unknown value fails with the valid list.
protocol LenientStringEnum: RawRepresentable<String>, CaseIterable, Codable, Sendable {}

extension LenientStringEnum {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let match = Self.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame }) else {
            let name = decoder.codingPath.last?.stringValue ?? "value"
            let valid = Self.allCases.map(\.rawValue).joined(separator: ", ")
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid \(name) '\(raw)'. Valid values: \(valid)."
            )
        }
        self = match
    }
}

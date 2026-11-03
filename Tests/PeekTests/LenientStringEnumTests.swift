import Foundation
@testable import peek
import Testing

@Suite("LenientStringEnum Tests")
struct LenientStringEnumTests {
    private struct Args: Decodable {
        let button: InteractionManager.MouseButton?
        let verify: ActionVerifyMode?
    }

    private func decode(_ json: String) throws -> Args {
        try JSONDecoder().decode(Args.self, from: Data(json.utf8))
    }

    @Test
    func decodesExactValues() throws {
        let args = try decode(#"{"button": "right", "verify": "diff"}"#)
        #expect(args.button == .right)
        #expect(args.verify == .diff)
    }

    @Test
    func decodingIgnoresCase() throws {
        let args = try decode(#"{"button": "Right", "verify": "TREE"}"#)
        #expect(args.button == .right)
        #expect(args.verify == .tree)
    }

    @Test
    func missingValuesStayNil() throws {
        let args = try decode("{}")
        #expect(args.button == nil)
        #expect(args.verify == nil)
    }

    @Test
    func unknownValueNamesTheArgumentAndValidValues() {
        do {
            _ = try decode(#"{"button": "middle"}"#)
            Issue.record("Expected a decoding error")
        } catch let DecodingError.dataCorrupted(context) {
            #expect(context.debugDescription == "Invalid button 'middle'. Valid values: left, right.")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func encodesRawValue() throws {
        let data = try JSONEncoder().encode([ActionVerifyMode.diff])
        #expect(String(decoding: data, as: UTF8.self) == #"["diff"]"#)
    }

    @Test
    func toolSchemasListTheAllowedValues() {
        #expect(PeekTools.click.inputSchema.properties?["button"]?.enum == ["left", "right"])
        #expect(PeekTools.action.inputSchema.properties?["verify"]?.enum == ["none", "tree", "diff"])
    }
}

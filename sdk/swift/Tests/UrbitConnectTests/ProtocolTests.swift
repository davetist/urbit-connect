import Foundation
import Testing
@testable import UrbitConnect

struct ProtocolTests {
    @Test func testSharedBoundaryFixtures() throws {
        struct Fixture: Decodable { let name: String; let input: String; let valid: Bool }
        let url = try #require(Bundle.module.url(forResource: "json-boundaries", withExtension: "json", subdirectory: "Fixtures"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        #expect(fixtures.count == 14)
        for fixture in fixtures {
            if fixture.valid { _ = try JSONValue.parse(Data(fixture.input.utf8)) }
            else { #expect(throws: ConnectError.self, "\(fixture.name)") { try JSONValue.parse(Data(fixture.input.utf8)) } }
        }
    }

    @Test func testMaximumDepthDocumentInChangeEnvelope() throws {
        var data: JSONObject = ["leaf": .string("deep")]
        for _ in 0..<15 { data = ["child": .object(data)] }
        let doc = ConnectDocument(id: UUID(), collection: "lists", data: data, revision: try Revision("1"), updatedAt: "2026-10-12T00:00:00Z")
        let wire: JSONObject = ["batches": .array([.object(["revision": .string("1"), "changes": .array([.object(["deleted": .bool(false), "document": .object(doc.wire)])])])]), "nextCursor": .string("1:1:1"), "hasMore": .bool(false)]
        let bytes = try JSONValue.object(wire).encoded(maxDepth: 24)
        let response = HTTPResponse(status: 200, body: bytes, retryAfter: nil)
        #expect(try response.json == wire)
        #expect(throws: ConnectError.self) { try JSONValue.object(["child": .object(data)]).encoded() }
    }
    @Test func testDocumentByteEncodingDoesNotInflateSlashes() throws {
        let doc: JSONObject = ["x": .string(String(repeating: "/", count: 16_384 - 8))]
        #expect(try JSONValue.object(doc).encoded(maxBytes: 16_384).count == 16_384)
    }
    @Test func testRevisionRoundTripAboveJavaScriptSafeInteger() throws {
        let revision = try Revision("9007199254740993")
        let wire = try JSONEncoder().encode(revision)
        #expect(String(decoding: wire, as: UTF8.self) == "\"9007199254740993\"")
        #expect(try JSONDecoder().decode(Revision.self, from: wire) == revision)
    }
    @Test func testRevisionMustBeCanonicalDecimal() {
        for value in ["", "01", "-1", "1.0", "1e3", "１２", "1/2"] {
            #expect(throws: ConnectError.self) { try Revision(value) }
        }
    }
    @Test func testDuplicateAndEscapedDuplicateKeysRejected() {
        for value in [#"{"a":1,"a":2}"#, #"{"a":1,"\u0061":2}"#] {
            #expect(throws: ConnectError.self) { try JSONValue.parse(Data(value.utf8)) }
        }
    }
    @Test func testNumbersAreLosslessAndPortable() throws {
        #expect(try JSONValue.parse(Data("1.2300e-10".utf8)) == .number("1.2300e-10"))
        for value in ["9007199254740993", "9.007199254740993e15", "9007199254740991.1", "1e9999", "NaN", "01"] {
            #expect(throws: ConnectError.self) { try JSONValue.parse(Data(value.utf8)) }
        }
        #expect(try JSONValue.parse(Data("9007199254740991".utf8)) == .number("9007199254740991"))
    }
    @Test func testDepthAndUTF8ByteLimit() throws {
        let deep = String(repeating: "[", count: 17) + "0" + String(repeating: "]", count: 17)
        #expect(throws: ConnectError.self) { try JSONValue.parse(Data(deep.utf8)) }
        #expect(throws: ConnectError.self) { try JSONValue.parse(Data("\"éé\"".utf8), maxBytes: 5) }
        #expect(try JSONValue.parse(Data("\"éé\"".utf8), maxBytes: 6) == .string("éé"))
    }
    @Test func testInvalidUnicodeAndTrailingBytesRejected() {
        for value in [#""\u0000""#, #""\uD800""#, "{} []"] {
            #expect(throws: ConnectError.self) { try JSONValue.parse(Data(value.utf8)) }
        }
        #expect(throws: ConnectError.self) { try JSONValue.parse(Data([34, 255, 34])) }
    }
    @Test func testDistinctUnicodeKeysRemainDistinct() throws {
        let value = try JSONValue.parse(Data(#"{"é":1,"e\u0301":2}"#.utf8))
        #expect(value.objectValue?.count == 2)
        #expect(try JSONValue.parse(value.encoded()) == value)
    }
    @Test func testExtremeNegativeExponentDoesNotOverflow() {
        #expect(throws: ConnectError.self) { try JSONValue.parse(Data("1e-9223372036854775808".utf8)) }
    }
    @Test func testIdentifiersRejectTraversalAndAmbiguity() {
        for value in ["", "A", "a/b", "a%2fb", "..", "tódos", String(repeating: "a", count: 49)] {
            #expect(!ConnectIdentifiers.collection(value))
        }
        #expect(ConnectIdentifiers.collection("todo-lists-2"))
        #expect(!ConnectIdentifiers.document("AAAAAAAA-aaaa-4aaa-8aaa-aaaaaaaaaaaa"))
        #expect(ConnectIdentifiers.document("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"))
    }
}

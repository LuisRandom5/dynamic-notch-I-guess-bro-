import Foundation
import Testing
@testable import DynamicNotch

@Suite struct PublicActivityAPITests {
    private func parse(_ json: String) throws -> PublicActivityAPI.Request {
        try PublicActivityAPI.parse(Data(json.utf8))
    }

    @Test func minimalStart() throws {
        let request = try parse(#"{"id":"build","title":"Compilando","progress":0.4}"#)
        #expect(request.id == "build")
        #expect(request.action == nil)
        #expect(request.progress == 0.4)
        #expect(request.placement == .bubble)
        #expect(request.alert == false)
    }

    @Test func rejectsBadIdsAndFields() {
        #expect(throws: PublicActivityAPI.ValidationError.missingId) { try parse(#"{"title":"x"}"#) }
        #expect(throws: PublicActivityAPI.ValidationError.invalidId) { try parse(#"{"id":"a b"}"#) }
        #expect(throws: PublicActivityAPI.ValidationError.invalidField("action")) { try parse(#"{"id":"a","action":"pause"}"#) }
        #expect(throws: PublicActivityAPI.ValidationError.invalidField("url")) { try parse(#"{"id":"a","url":"file:///etc/passwd"}"#) }
        #expect(throws: PublicActivityAPI.ValidationError.invalidField("color")) { try parse(##"{"id":"a","color":"#12"}"##) }
        #expect(throws: PublicActivityAPI.ValidationError.invalidJSON) { try parse("nope") }
    }

    @Test func rejectsPayloadsOver4KB() {
        let big = String(repeating: "x", count: 5000)
        #expect(throws: PublicActivityAPI.ValidationError.tooLarge) { try parse(#"{"id":"a","title":"\#(big)"}"#) }
    }

    @Test func clampsAndAcceptsTextNumbers() throws {
        let request = try PublicActivityAPI.parse(["id": "dl", "progress": "1.7", "relevance": "5000", "alert": ["sound": true]])
        #expect(request.progress == 1)
        #expect(request.relevance == 1000)
        #expect(request.alert && request.sound)
    }

    @Test func colorsByNameOrHex() {
        #expect(PublicActivityAPI.color(from: "#34C759") != nil)
        #expect(PublicActivityAPI.color(from: "green") != nil)
        #expect(PublicActivityAPI.color(from: "verde") == nil)
    }
}

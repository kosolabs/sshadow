import Testing

@testable import Common

@Suite("PrettyDescribable")
struct PrettyDescribableTests {
    @Test("Enum case without associated values renders type and case")
    func caseWithoutPayload() {
        #expect(
            "\(CoreError.serverUnreachable)" == "CoreError.serverUnreachable"
        )
        #expect("\(OnExists.fail)" == "OnExists.fail")
    }

    @Test("Optional payload renders nil or a quoted string")
    func optionalPayload() {
        #expect("\(CoreError.itemNotFound)" == "CoreError.itemNotFound(nil)")
        #expect(
            "\(CoreError.itemNotFound("abc"))"
                == "CoreError.itemNotFound(\"abc\")"
        )
    }

    @Test("Labelled payloads render as labelled fields")
    func labelledPayload() {
        let error = CoreError.unknown(domain: "d", code: 3, message: "boom")
        #expect(
            "\(error)"
                == "CoreError.unknown(domain: \"d\", code: 3, message: \"boom\")"
        )
    }

    @Test("Nested values use their own pretty description")
    func nestedValue() {
        #expect(
            "\(CoreResult.failure(.serverUnreachable))"
                == "CoreResult.failure(CoreError.serverUnreachable)"
        )
    }

    @Test("Structs render their fields")
    func structFields() {
        let request = NameRequest(itemId: "abc")
        #expect("\(request)" == "NameRequest(itemId: \"abc\")")
    }
}

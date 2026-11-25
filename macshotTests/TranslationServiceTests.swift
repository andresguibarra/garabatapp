import XCTest

final class TranslationServiceTests: XCTestCase {

    private func parse(_ body: String) -> Result<String, TranslationError> {
        TranslationService.parseGoogleResponse(Data(body.utf8))
    }

    func testParsesMultiSegmentResponseWithAccentsAndQuotes() {
        let body = #"[[["I think we are going to rethink the escape issue.\n","Creo que vamos a repensar el tema del escape.\n",null,null,10],["It says \"selected\".","Dice \"seleccionado\".",null,null,3,null,null,[[]],[[["x","y"]]]]],null,"es",null,null,null,1,[],[["es"],null,[1],["es"]]]"#
        XCTAssertEqual(try parse(body).get(),
                       "I think we are going to rethink the escape issue.\nIt says \"selected\".")
    }

    func testSkipsSegmentsWithoutOutputText() {
        let body = #"[[["Hello ","Hola ",null,null,1],[null,null,"OH-la"]],null,"es"]"#
        XCTAssertEqual(try parse(body).get(), "Hello ")
    }

    func testStripsXSSIPrefix() {
        XCTAssertEqual(try parse(")]}'\n[[[\"Hi\",\"Hola\"]],null,\"es\"]").get(), "Hi")
    }

    func testAcceptsBareStringVariants() {
        XCTAssertEqual(try parse(#"[["Hi","es"]]"#).get(), "Hi")
        XCTAssertEqual(try parse(#"["Hi","es"]"#).get(), "Hi")
        XCTAssertEqual(try parse(#""Hi""#).get(), "Hi")
    }

    func testHTMLBlockPageIsReportedAsBlocked() {
        let html = "<html><head><title>Sorry...</title></head><body>unusual traffic</body></html>"
        guard case .failure(.blocked) = parse(html) else { return XCTFail("expected .blocked") }
    }

    func testGarbageIsParseErrorAndNullIsEmpty() {
        guard case .failure(.parseError) = parse("not json") else { return XCTFail() }
        guard case .failure(.emptyResult) = parse("[null,null,\"es\"]") else { return XCTFail() }
    }

    func testErrorMessagesExplainWhatToDo() {
        for error in [TranslationError.rateLimited, .blocked, .httpStatus(503), .parseError] {
            XCTAssertTrue(error.localizedDescription.contains("Apple Translation"), "\(error)")
        }
    }

    func testChunksJoinLinesUnderLimitAndSkipEmpty() {
        let texts = ["Creo que vamos", "", "a repensar", String(repeating: "á", count: 30), "fin"]
        XCTAssertEqual(TranslationService.googleChunks(for: texts, limit: 1800), [[0, 2, 3, 4]])
        XCTAssertEqual(TranslationService.googleChunks(for: texts, limit: 30), [[0, 2], [3], [4]])
    }

    func testGoogleLineFlattensInternalNewlines() {
        XCTAssertEqual(TranslationService.googleLine("  uno\n dos \r\ntres "), "uno dos tres")
    }

    func testSplitMatchesLineCountOrFallsBack() {
        XCTAssertEqual(TranslationService.splitGoogleLines("a\nb \n c\n", expected: 3), ["a", "b", "c"])
        XCTAssertNil(TranslationService.splitGoogleLines("a b\nc", expected: 3))
        XCTAssertNil(TranslationService.splitGoogleLines("a\n\nc", expected: 3))
    }
}

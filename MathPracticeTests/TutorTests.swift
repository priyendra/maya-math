import XCTest
@testable import MathPractice

final class TutorTests: XCTestCase {
    func testParserHandlesLinesSplitAcrossChunks() {
        var p = TutorScriptParser()
        var beats: [TutorBeat] = []
        for chunk in ["SAY: Hi th", "ere!\nPOI", "NT: s2\nWRITE: $x^2 - 9$\n", "POINT: none\nSAY: Done"] {
            beats += p.feed(chunk)
        }
        beats += p.finish()
        XCTAssertEqual(beats, [.say("Hi there!"), .point("s2"), .write("$x^2 - 9$"), .point(nil), .say("Done")])
    }

    func testUntaggedLinesAndSpokenCleanup() {
        XCTAssertEqual(TutorScriptParser.beat("$(1-3a)(1+3a)$"), .write("$(1-3a)(1+3a)$"))
        XCTAssertEqual(TutorScriptParser.beat("Nice work."), .say("Nice work."))
        XCTAssertEqual(TutorScriptParser.beat("say: It's $9a^2$ here"), .say("It's 9a squared here"))
        XCTAssertEqual(TutorScriptParser.beat("POINT: [S3]"), .point("s3"))
        XCTAssertNil(TutorScriptParser.beat("   "))
    }

    func testVariableLettersAreSaidByName() {
        XCTAssertEqual(TutorScriptParser.spoken("The square root of nine [a] squared is three [a]."),
                       "The square root of nine ay squared is three ay.")
        XCTAssertEqual(TutorScriptParser.spoken("the square root of nine a squared is three a, not nine a."),
                       "the square root of nine ay squared is three ay, not nine ay.")
        XCTAssertEqual(TutorScriptParser.spoken("using a equals x cubed"), "using ay equals x cubed")
        XCTAssertEqual(TutorScriptParser.spoken("x plus a, which is a perfect square"), "x plus ay, which is a perfect square")
        XCTAssertEqual(TutorScriptParser.spoken("That's a good question with a twist."), "That's a good question with a twist.")
        XCTAssertEqual(TutorScriptParser.spoken("plus a little more"), "plus a little more")
    }

    func testSolutionSteps() {
        let sol = "1. Write each term as a square: $1 = 1^2$.\n2. So\n$$1-9a^2 = (1-3a)(1+3a)$$\n3. Check. ✓"
        XCTAssertEqual(TutorScriptParser.steps(sol), ["1. Write each term as a square: $1 = 1^2$.", "2. So\n$$1-9a^2 = (1-3a)(1+3a)$$", "3. Check. ✓"])
        XCTAssertEqual(TutorScriptParser.steps("First idea.\n\nSecond idea."), ["First idea.", "Second idea."])
    }

    func testSSEReturnsTextDeltas() throws {
        var acc = SSEAccumulator()
        XCTAssertNil(try acc.consume(line: #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#))
        XCTAssertNil(try acc.consume(line: #"data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#))
        XCTAssertEqual(try acc.consume(line: #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"SAY: Hi"}}"#), "SAY: Hi")
    }
}

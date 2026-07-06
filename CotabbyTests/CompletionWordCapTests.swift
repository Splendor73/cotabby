import XCTest
@testable import Cotabby

/// The user's word-count setting was prompt guidance only — models overrun it freely, and long
/// ghost text reads slower, decodes slower, and is the single biggest "feel" difference from the
/// competitor's hard 7-word cap. The cap trims at word starts and preserves the original
/// spacing/punctuation of everything it keeps.
final class CompletionWordCapTests: XCTestCase {
    func testShortCompletionPassesThrough() {
        XCTAssertEqual(CompletionWordCap.trim("to the store", maxWords: 7), "to the store")
    }

    func testTrimsToTheCapAtWordStarts() {
        XCTAssertEqual(
            CompletionWordCap.trim("one two three four five six seven eight nine", maxWords: 7),
            "one two three four five six seven"
        )
    }

    func testPreservesLeadingSpaceAndInnerPunctuation() {
        XCTAssertEqual(
            CompletionWordCap.trim(" we'll meet at 3:30, then head out for dinner", maxWords: 5),
            " we'll meet at 3:30, then"
        )
    }

    func testExactCapIsUntouched() {
        XCTAssertEqual(CompletionWordCap.trim("a b c", maxWords: 3), "a b c")
    }

    func testZeroOrNegativeCapReturnsTextUnchanged() {
        XCTAssertEqual(CompletionWordCap.trim("hello world", maxWords: 0), "hello world")
        XCTAssertEqual(CompletionWordCap.trim("hello world", maxWords: -2), "hello world")
    }

    func testWhitespaceOnlyTextPassesThrough() {
        XCTAssertEqual(CompletionWordCap.trim("   ", maxWords: 3), "   ")
    }

    func testTrailingWhitespaceAfterCutIsDropped() {
        XCTAssertEqual(
            CompletionWordCap.trim("alpha beta   gamma delta", maxWords: 2),
            "alpha beta"
        )
    }
}

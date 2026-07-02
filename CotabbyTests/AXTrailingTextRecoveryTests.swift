import XCTest
@testable import Cotabby

/// Pins the recovery rules for the Electron/Chromium trailing-text hole: hosts that answer the
/// before/selected `AXStringForRange` reads but return nil or empty for the trailing range even
/// though their own `AXNumberOfCharacters` proves characters follow the caret. Treating that
/// answer as "no trailing text" made mid-line carets look end-of-line and let inline ghost text
/// paint over the user's real text.
final class AXTrailingTextRecoveryTests: XCTestCase {
    // MARK: - needsRecovery

    func test_noTrailingCharacters_needsNoRecovery() {
        XCTAssertFalse(AXTrailingTextRecovery.needsRecovery(afterLength: 0, nativeTrailingText: nil))
        XCTAssertFalse(AXTrailingTextRecovery.needsRecovery(afterLength: 0, nativeTrailingText: ""))
    }

    func test_nilReadWithTrailingCharacters_needsRecovery() {
        XCTAssertTrue(AXTrailingTextRecovery.needsRecovery(afterLength: 12, nativeTrailingText: nil))
    }

    func test_emptyReadWithTrailingCharacters_needsRecovery() {
        // A successful-but-empty answer for a non-empty range is the same lie as a nil answer.
        XCTAssertTrue(AXTrailingTextRecovery.needsRecovery(afterLength: 12, nativeTrailingText: ""))
    }

    func test_realTrailingText_needsNoRecovery() {
        XCTAssertFalse(AXTrailingTextRecovery.needsRecovery(afterLength: 12, nativeTrailingText: " rest of line"))
    }

    // MARK: - slicedTrailingText

    func test_slicesTrailingWindowFromFullValue() {
        XCTAssertEqual(
            AXTrailingTextRecovery.slicedTrailingText(fullText: "hello world", afterStart: 5, afterLength: 6),
            " world"
        )
    }

    func test_sliceReachingExactEndOfValue() {
        XCTAssertEqual(
            AXTrailingTextRecovery.slicedTrailingText(fullText: "abc", afterStart: 1, afterLength: 2),
            "bc"
        )
    }

    func test_valueShorterThanAdvertisedDocumentLength_returnsNil() {
        // Electron sometimes disagrees with its own AXNumberOfCharacters; slicing would read out
        // of bounds, so the caller must fall back to the whole-value selection instead.
        XCTAssertNil(AXTrailingTextRecovery.slicedTrailingText(fullText: "abc", afterStart: 2, afterLength: 5))
    }

    func test_afterStartBeyondValue_returnsNil() {
        XCTAssertNil(AXTrailingTextRecovery.slicedTrailingText(fullText: "abc", afterStart: 7, afterLength: 1))
    }

    func test_zeroOrNegativeInputs_returnNil() {
        XCTAssertNil(AXTrailingTextRecovery.slicedTrailingText(fullText: "abc", afterStart: -1, afterLength: 2))
        XCTAssertNil(AXTrailingTextRecovery.slicedTrailingText(fullText: "abc", afterStart: 0, afterLength: 0))
    }

    func test_sliceCountsUTF16Units() {
        // AX ranges are UTF-16 unit offsets; "🙂" occupies two units, so afterStart 2 begins after it.
        XCTAssertEqual(
            AXTrailingTextRecovery.slicedTrailingText(fullText: "🙂ab", afterStart: 2, afterLength: 2),
            "ab"
        )
    }
}

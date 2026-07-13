import CoreGraphics
import XCTest
@testable import Cotabby

/// The popup card holds its screen position while the user types along one line and only moves
/// when the caret changes line. A card that chases the caret rightward on every keystroke is a
/// moving target the eye cannot track at speed — pinning it makes it a stable thing to read.
final class MirrorCardPinPolicyTests: XCTestCase {
    func testFirstShowAlwaysAnchors() {
        XCTAssertTrue(
            MirrorCardPinPolicy.shouldReanchor(pinnedCaretMinY: nil, liveCaretMinY: 400, caretHeight: 18)
        )
    }

    func testSameLineDoesNotReanchor() {
        XCTAssertFalse(
            MirrorCardPinPolicy.shouldReanchor(pinnedCaretMinY: 400, liveCaretMinY: 400, caretHeight: 18)
        )
    }

    func testSubLineJitterIsAbsorbed() {
        // Derived/estimated carets wobble a few points on the same visual line; that must not
        // count as a line change or the card would twitch.
        XCTAssertFalse(
            MirrorCardPinPolicy.shouldReanchor(pinnedCaretMinY: 400, liveCaretMinY: 404, caretHeight: 18)
        )
    }

    func testMovingDownOneLineReanchors() {
        XCTAssertTrue(
            MirrorCardPinPolicy.shouldReanchor(pinnedCaretMinY: 400, liveCaretMinY: 382, caretHeight: 18)
        )
    }

    func testMovingUpOneLineReanchors() {
        XCTAssertTrue(
            MirrorCardPinPolicy.shouldReanchor(pinnedCaretMinY: 400, liveCaretMinY: 418, caretHeight: 18)
        )
    }

    func testTinyCaretUsesTheSixPointFloor() {
        // caretHeight * 0.5 = 4 < 6, so the 6pt floor governs.
        XCTAssertFalse(
            MirrorCardPinPolicy.shouldReanchor(pinnedCaretMinY: 400, liveCaretMinY: 405, caretHeight: 8)
        )
        XCTAssertTrue(
            MirrorCardPinPolicy.shouldReanchor(pinnedCaretMinY: 400, liveCaretMinY: 407, caretHeight: 8)
        )
    }
}

import XCTest
@testable import Cotabby

/// The screen excerpt is captured once per field focus, so in a long-lived chat field it
/// describes a conversation state from minutes ago while the model is asked about the reply
/// being written NOW. Refresh only when both are true: the excerpt is genuinely old AND the
/// user is pausing — a refresh swaps the prompt head, and that rebuild must happen during a
/// pause, never on a keystroke.
final class ExcerptRefreshPolicyTests: XCTestCase {
    func testRefreshesOldExcerptDuringAPause() {
        XCTAssertTrue(ExcerptRefreshPolicy.shouldRefresh(excerptAgeSeconds: 45, idleSeconds: 3))
    }

    func testFreshExcerptIsLeftAlone() {
        XCTAssertFalse(ExcerptRefreshPolicy.shouldRefresh(excerptAgeSeconds: 10, idleSeconds: 5))
    }

    func testNeverRefreshesMidTyping() {
        XCTAssertFalse(ExcerptRefreshPolicy.shouldRefresh(excerptAgeSeconds: 120, idleSeconds: 0.4))
    }

    func testUnknownIdleMeansNoRefresh() {
        XCTAssertFalse(ExcerptRefreshPolicy.shouldRefresh(excerptAgeSeconds: 120, idleSeconds: nil))
    }
}

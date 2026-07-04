import XCTest
@testable import Cotabby

/// During fluent typing most generations finish just after the next keystroke has already
/// superseded their work id, and the finished text is discarded — so ghost text only ever
/// appears at pauses. Recording those results into the anchor cache lets the audited restore
/// path re-serve the typed-through remainder on the live cycle. The policy decides which stale
/// results are safe to remember: staleness must be the ONLY reason the result went unused.
final class StaleResultRescuePolicyTests: XCTestCase {
    private func record(
        isEnabled: Bool = true,
        isTaskCancelled: Bool = false,
        isSpeculative: Bool = false,
        isSecure: Bool = false,
        normalizedText: String = "world"
    ) -> Bool {
        StaleResultRescuePolicy.shouldRecord(
            isEnabled: isEnabled,
            isTaskCancelled: isTaskCancelled,
            isSpeculative: isSpeculative,
            isSecure: isSecure,
            normalizedText: normalizedText
        )
    }

    func testRecordsAPlainStaleResult() {
        XCTAssertTrue(record())
    }

    func testRefusesWhenFeatureFlagIsOff() {
        XCTAssertFalse(record(isEnabled: false))
    }

    func testRefusesTeardownCancellation_staleWorkIDaloneIsNotEnough() {
        // cancelAll (global toggle-off, per-app disable, emoji picker takeover) cancels the task;
        // a keystroke supersede only retires the work id. Only the latter may be rescued.
        XCTAssertFalse(record(isTaskCancelled: true))
    }

    func testRefusesSpeculativeRequests() {
        // A speculative post-acceptance result was built against text the host never confirmed;
        // its own signature validation is the only safe consumer.
        XCTAssertFalse(record(isSpeculative: true))
    }

    func testRefusesSecureFieldResults() {
        // The anchor cache stores the preceding-text tail in plain strings.
        XCTAssertFalse(record(isSecure: true))
    }

    func testRefusesEmptyNormalizedText() {
        XCTAssertFalse(record(normalizedText: ""))
    }
}

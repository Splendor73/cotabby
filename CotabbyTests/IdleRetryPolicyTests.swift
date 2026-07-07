import XCTest
@testable import Cotabby

/// When the model returns nothing at a thinking-pause, one seed-walked regeneration is allowed —
/// the competitor always offers something, and a different seed frequently dodges whatever made
/// the first attempt mute. Exactly one per content signature: without the cap, persistently
/// silent content (a genuinely finished sentence) would regenerate in a loop at every pause.
final class IdleRetryPolicyTests: XCTestCase {
    func testFirstEmptyForASignatureRetries() {
        XCTAssertTrue(IdleRetryPolicy.shouldRetry(emptySignature: "sig-a", lastRetriedSignature: nil))
        XCTAssertTrue(IdleRetryPolicy.shouldRetry(emptySignature: "sig-b", lastRetriedSignature: "sig-a"))
    }

    func testSameSignatureNeverRetriesTwice() {
        XCTAssertFalse(IdleRetryPolicy.shouldRetry(emptySignature: "sig-a", lastRetriedSignature: "sig-a"))
    }
}

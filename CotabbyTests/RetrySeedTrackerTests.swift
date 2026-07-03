import XCTest
@testable import Cotabby

/// Pins the retry-seed rules: the sampler seed is fixed so identical contexts reproduce identical
/// ghost text — good for stability, terrible after a dismissal, where a regeneration for the very
/// same content silently reproduced the very suggestion the user just rejected. The tracker arms
/// on dismissal and hands later same-signature generations a varied-but-deterministic seed;
/// any content change stands down.
final class RetrySeedTrackerTests: XCTestCase {
    private let signature = "0::0::hello world::::plain"
    private let otherSignature = "0::0::something else::::plain"

    func test_unarmed_returnsNoOverride() {
        var tracker = RetrySeedTracker()
        XCTAssertNil(tracker.seedOverride(for: signature))
    }

    func test_dismissalArmsSameSignatureRetry() {
        var tracker = RetrySeedTracker()
        tracker.noteDismissal(contentSignature: signature)
        XCTAssertEqual(tracker.seedOverride(for: signature), RetrySeedTracker.baseSeed &+ 1)
    }

    func test_repeatedQueriesForSameRetryAreStable() {
        // A re-show of the same retry (overlay redraw, geometry refresh) must not walk the seed.
        var tracker = RetrySeedTracker()
        tracker.noteDismissal(contentSignature: signature)
        XCTAssertEqual(tracker.seedOverride(for: signature), tracker.seedOverride(for: signature))
    }

    func test_secondDismissalWalksTheSeed() {
        var tracker = RetrySeedTracker()
        tracker.noteDismissal(contentSignature: signature)
        tracker.noteDismissal(contentSignature: signature)
        XCTAssertEqual(tracker.seedOverride(for: signature), RetrySeedTracker.baseSeed &+ 2)
    }

    func test_signatureChangeStandsDown() {
        var tracker = RetrySeedTracker()
        tracker.noteDismissal(contentSignature: signature)
        XCTAssertNil(tracker.seedOverride(for: otherSignature), "typing produced new content — no retry")
        XCTAssertNil(
            tracker.seedOverride(for: signature),
            "a stand-down is permanent: returning to old content is not a retry either"
        )
    }

    func test_dismissalOfDifferentContentRestartsCount() {
        var tracker = RetrySeedTracker()
        tracker.noteDismissal(contentSignature: signature)
        tracker.noteDismissal(contentSignature: otherSignature)
        XCTAssertEqual(tracker.seedOverride(for: otherSignature), RetrySeedTracker.baseSeed &+ 1)
    }

    func test_baseSeedMatchesTheEngineDefault() {
        // The override must extend the engine's own fixed seed so retry #0 (no dismissal) and the
        // engine default stay the same stream; a drifted constant would silently change every
        // first suggestion instead of only retries.
        XCTAssertEqual(RetrySeedTracker.baseSeed, LlamaRuntimeCore.defaultSamplerSeed)
    }
}

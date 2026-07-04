import XCTest
@testable import Cotabby

/// A spell-checker correction painted mid-burst is invalidated by the very next keystroke
/// 20-140ms later — live logs show up to three paint/vanish cycles per second of green ghost
/// text while typing through a word. The policy defers presentation until the keyboard has been
/// quiet long enough that the correction can actually be read: present immediately only when the
/// last keystroke is old enough, otherwise report how long to wait before re-checking.
final class CorrectionIdlePolicyTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    func testPresentsImmediatelyWithNoRecordedKeystroke() {
        XCTAssertNil(
            CorrectionIdlePolicy.remainingDelayMilliseconds(now: base, lastKeystrokeAt: nil)
        )
    }

    func testPresentsImmediatelyWhenKeyboardHasBeenIdlePastThreshold() {
        let last = base.addingTimeInterval(-0.400)
        XCTAssertNil(
            CorrectionIdlePolicy.remainingDelayMilliseconds(now: base, lastKeystrokeAt: last)
        )
    }

    func testDefersByTheRemainingIdleTimeMidBurst() {
        let last = base.addingTimeInterval(-0.100)
        XCTAssertEqual(
            CorrectionIdlePolicy.remainingDelayMilliseconds(now: base, lastKeystrokeAt: last),
            CorrectionIdlePolicy.idleThresholdMilliseconds - 100
        )
    }

    func testExactThresholdBoundaryPresentsImmediately() {
        let last = base.addingTimeInterval(
            -Double(CorrectionIdlePolicy.idleThresholdMilliseconds) / 1000
        )
        XCTAssertNil(
            CorrectionIdlePolicy.remainingDelayMilliseconds(now: base, lastKeystrokeAt: last)
        )
    }

    func testClockSkewFallsBackToFullThreshold() {
        let last = base.addingTimeInterval(0.500)
        XCTAssertEqual(
            CorrectionIdlePolicy.remainingDelayMilliseconds(now: base, lastKeystrokeAt: last),
            CorrectionIdlePolicy.idleThresholdMilliseconds
        )
    }
}

import XCTest
@testable import Cotabby

/// Verifies the pure coalescing decision behind `VisualContextCoordinator.startSessionIfNeeded`.
/// This is the #280 fix: focus flapping (Chrome losing and re-acquiring the AX field) must not
/// restart the screenshot -> OCR -> summarize pipeline on every flap. Flaps bump the monotonic
/// `focusChangeSequence` while the element and process stay put, so field identity here is
/// process + element and deliberately ignores the sequence — measured live (2026-07-05), the
/// sequence-exact comparison caused 71 capture sessions and a prompt-head rewrite per flap,
/// collapsing llama KV reuse to 8 of 289 decodes.
final class VisualContextStartCoalescerTests: XCTestCase {
    private func id(
        _ element: String,
        _ sequence: UInt64,
        pid: Int32 = 100
    ) -> VisualContextFieldIdentity {
        VisualContextFieldIdentity(
            processIdentifier: pid,
            elementIdentifier: element,
            focusChangeSequence: sequence
        )
    }

    func test_noActiveOrPending_starts() {
        XCTAssertEqual(
            VisualContextStartCoalescer.decide(
                incoming: id("field", 1), active: nil,
                activeIsBlockedOnScreenRecording: false,
                hasScreenRecordingPermission: true, pending: nil
            ),
            .start
        )
    }

    func test_sameAsActiveField_isIgnored() {
        XCTAssertEqual(
            VisualContextStartCoalescer.decide(
                incoming: id("field", 1), active: id("field", 1),
                activeIsBlockedOnScreenRecording: false,
                hasScreenRecordingPermission: true, pending: nil
            ),
            .ignore
        )
    }

    /// The flap case: Chromium re-acquires the same element and the tracker bumps the sequence.
    /// The active capture (and its served excerpt) must survive.
    func test_sameElementBumpedSequence_activeField_isIgnored() {
        XCTAssertEqual(
            VisualContextStartCoalescer.decide(
                incoming: id("field", 2), active: id("field", 1),
                activeIsBlockedOnScreenRecording: false,
                hasScreenRecordingPermission: true, pending: nil
            ),
            .ignore
        )
    }

    /// Same flap while the field is still waiting out its settle window.
    func test_sameElementBumpedSequence_pendingField_isIgnored() {
        XCTAssertEqual(
            VisualContextStartCoalescer.decide(
                incoming: id("field", 8), active: nil,
                activeIsBlockedOnScreenRecording: false,
                hasScreenRecordingPermission: true, pending: id("field", 7)
            ),
            .ignore
        )
    }

    /// A genuinely different element re-arms the capture.
    func test_differentElement_starts() {
        XCTAssertEqual(
            VisualContextStartCoalescer.decide(
                incoming: id("field-b", 2), active: id("field-a", 1),
                activeIsBlockedOnScreenRecording: false,
                hasScreenRecordingPermission: true, pending: id("other", 5)
            ),
            .start
        )
    }

    /// macOS recycles CFHash-based element tokens across processes; the process id is what keeps
    /// a recycled hash in another app from silently inheriting this field's screen context.
    func test_sameElementDifferentProcess_starts() {
        XCTAssertEqual(
            VisualContextStartCoalescer.decide(
                incoming: id("field", 2, pid: 200), active: id("field", 1, pid: 100),
                activeIsBlockedOnScreenRecording: false,
                hasScreenRecordingPermission: true, pending: nil
            ),
            .start
        )
    }

    func test_activeBlockedOnPermission_recoversWhenGranted() {
        XCTAssertEqual(
            VisualContextStartCoalescer.decide(
                incoming: id("field", 1), active: id("field", 1),
                activeIsBlockedOnScreenRecording: true,
                hasScreenRecordingPermission: true, pending: nil
            ),
            .recoverPermissionThenStart
        )
    }

    /// Permission recovery must also tolerate the flap's bumped sequence.
    func test_activeBlockedOnPermission_recoversAcrossFlap() {
        XCTAssertEqual(
            VisualContextStartCoalescer.decide(
                incoming: id("field", 3), active: id("field", 1),
                activeIsBlockedOnScreenRecording: true,
                hasScreenRecordingPermission: true, pending: nil
            ),
            .recoverPermissionThenStart
        )
    }

    func test_activeBlockedButPermissionStillMissing_isIgnored() {
        XCTAssertEqual(
            VisualContextStartCoalescer.decide(
                incoming: id("field", 1), active: id("field", 1),
                activeIsBlockedOnScreenRecording: true,
                hasScreenRecordingPermission: false, pending: nil
            ),
            .ignore
        )
    }
}

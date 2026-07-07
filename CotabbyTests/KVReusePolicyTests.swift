import XCTest
@testable import Cotabby

/// Pins the KV reuse decisions for both cache families. Dense models rewind by trimming; the
/// hybrid/SWA catalog models reject every partial trim, so their path is snapshot-restore
/// (capture prompt-only state after prefill, put it back instead of trimming) plus a skip-trim
/// branch for pure extensions, where the restored cache already sits exactly at the reusable
/// prefix and calling trim at all would hand llama.cpp an empty-range removal it may reject.
final class KVReusePolicyTests: XCTestCase {
    // MARK: - Reuse decision (prompt arrival)

    func test_denseModel_rewindsByTrimming() {
        XCTAssertEqual(
            KVReusePolicy.reuseDecision(
                modelRejectsPartialTrims: false, reusableTokenCount: 120, decodedTokenCount: 150
            ),
            .trimThenDecode
        )
    }

    func test_pureExtension_skipsTheTrimEntirely() {
        // Cache sits exactly at the reusable prefix (restored prompt-only state): decoding the
        // delta needs no rewind, and an empty-range trim is exactly what hybrids reject.
        XCTAssertEqual(
            KVReusePolicy.reuseDecision(
                modelRejectsPartialTrims: true, reusableTokenCount: 150, decodedTokenCount: 150
            ),
            .decodeDeltaWithoutTrim
        )
    }

    func test_denseModelAtExactPrefix_alsoSkipsTheNoOpTrim() {
        XCTAssertEqual(
            KVReusePolicy.reuseDecision(
                modelRejectsPartialTrims: false, reusableTokenCount: 150, decodedTokenCount: 150
            ),
            .decodeDeltaWithoutTrim
        )
    }

    func test_hybridModelNeedingRealRewind_rebuildsFresh() {
        // The user edited earlier text: the cache holds more than the common prefix and hybrids
        // cannot rewind. Trying the trim anyway would just log another rejection.
        XCTAssertEqual(
            KVReusePolicy.reuseDecision(
                modelRejectsPartialTrims: true, reusableTokenCount: 120, decodedTokenCount: 150
            ),
            .rebuildFresh
        )
    }

    func test_nothingReusable_rebuildsFresh() {
        XCTAssertEqual(
            KVReusePolicy.reuseDecision(
                modelRejectsPartialTrims: false, reusableTokenCount: 0, decodedTokenCount: 150
            ),
            .rebuildFresh
        )
    }

    // MARK: - Post-generation action (returning the cache to prompt-only)

    func test_denseModel_trimsSampledTokensAway() {
        XCTAssertEqual(
            KVReusePolicy.postGenerationAction(
                modelRejectsPartialTrims: false, hasSnapshotForCurrentPrompt: false,
                abortFlagged: false, samplerTouched: true
            ),
            .trim
        )
    }

    func test_hybridWithSnapshot_restoresInsteadOfTrimming() {
        XCTAssertEqual(
            KVReusePolicy.postGenerationAction(
                modelRejectsPartialTrims: true, hasSnapshotForCurrentPrompt: true,
                abortFlagged: false, samplerTouched: true
            ),
            .restoreSnapshot
        )
    }

    func test_hybridWithoutSnapshot_probesTheTrim() {
        // First generation after model load: the rejection flag is learned from this very trim,
        // so the probe must still run (its failure is what turns the snapshot path on).
        XCTAssertEqual(
            KVReusePolicy.postGenerationAction(
                modelRejectsPartialTrims: true, hasSnapshotForCurrentPrompt: false,
                abortFlagged: false, samplerTouched: true
            ),
            .trim
        )
    }

    /// The engine's per-sequence cancel flag is set-once: a sequence the abort ever touched will
    /// fake-cancel every future decode on it. Keeping one as reusable cache was the 7x paint
    /// regression (91ea45b, reverted) — the flagged sequence must be destroyed, regardless of
    /// anything else.
    func test_abortFlaggedSequence_isDestroyed_neverKept() {
        XCTAssertEqual(
            KVReusePolicy.postGenerationAction(
                modelRejectsPartialTrims: true, hasSnapshotForCurrentPrompt: true,
                abortFlagged: true, samplerTouched: false
            ),
            .destroySequence
        )
        XCTAssertEqual(
            KVReusePolicy.postGenerationAction(
                modelRejectsPartialTrims: false, hasSnapshotForCurrentPrompt: false,
                abortFlagged: true, samplerTouched: true
            ),
            .destroySequence
        )
    }

    /// A generation cancelled between prefill and its first sample, with no abort fired, left the
    /// sequence clean and exactly prompt-only: keep it live. The next keystroke's prompt is a
    /// pure extension on base-renderer models, so this is a free decodeDeltaWithoutTrim hit —
    /// and the ~300ms restore memcpy the old path paid here bought nothing.
    func test_cleanUnflaggedUnsampledCancel_keepsLiveState() {
        XCTAssertEqual(
            KVReusePolicy.postGenerationAction(
                modelRejectsPartialTrims: true, hasSnapshotForCurrentPrompt: true,
                abortFlagged: false, samplerTouched: false
            ),
            .keepLiveState
        )
        XCTAssertEqual(
            KVReusePolicy.postGenerationAction(
                modelRejectsPartialTrims: false, hasSnapshotForCurrentPrompt: false,
                abortFlagged: false, samplerTouched: false
            ),
            .keepLiveState
        )
    }

    /// An immediate end-of-text ran the sampler once (the seed advanced sampler history even
    /// with zero committed tokens): that sequence is TOUCHED and must take the normal
    /// restore/trim path, not the keep-live shortcut.
    func test_immediateEOS_countsAsTouched() {
        XCTAssertEqual(
            KVReusePolicy.postGenerationAction(
                modelRejectsPartialTrims: true, hasSnapshotForCurrentPrompt: true,
                abortFlagged: false, samplerTouched: true
            ),
            .restoreSnapshot
        )
    }

    // MARK: - Snapshot capture policy

    func test_capturesOnlyOnTrimRejectingModels() {
        XCTAssertFalse(
            KVReusePolicy.shouldCaptureSnapshot(
                modelRejectsPartialTrims: false, snapshotSizeBytes: 1_000_000
            ),
            "dense models trim for free; a snapshot would be pure memcpy waste"
        )
        XCTAssertTrue(
            KVReusePolicy.shouldCaptureSnapshot(
                modelRejectsPartialTrims: true, snapshotSizeBytes: 1_000_000
            )
        )
    }

    func test_declinesOversizedSnapshots() {
        XCTAssertFalse(
            KVReusePolicy.shouldCaptureSnapshot(
                modelRejectsPartialTrims: true,
                snapshotSizeBytes: KVReusePolicy.maximumSnapshotBytes + 1
            ),
            "a snapshot bigger than the cap costs more to copy than the re-prefill it saves"
        )
        XCTAssertFalse(
            KVReusePolicy.shouldCaptureSnapshot(modelRejectsPartialTrims: true, snapshotSizeBytes: 0),
            "a zero size means the engine could not report state for this sequence"
        )
    }
}

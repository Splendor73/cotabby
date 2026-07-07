import Foundation

/// File overview:
/// Pure decision rules for llama KV-cache reuse across both cache families.
///
/// Why this file exists: dense-attention models rewind their cache by trimming, but the
/// hybrid/SWA catalog models reject every partial trim (`llama_memory_seq_rm` fails on
/// recurrent-style state), which used to force a full prompt re-prefill on every request.
/// Their fast path is snapshot-restore: capture the prompt-only sequence state once after
/// prefill, and after generation put the captured state back instead of trimming. That leaves
/// exactly one trim the reuse path would still issue — the empty-range "trim to where the cache
/// already is" on a pure typing extension — and hybrids reject that too, so the policy skips it
/// outright. `LlamaRuntimeCore` owns all native calls; this type only decides.
enum KVReusePolicy {
    /// Snapshots above this size cost more to copy per request than the re-prefill they save;
    /// decline them and keep today's rebuild behavior.
    static let maximumSnapshotBytes = 512 * 1024 * 1024

    enum ReuseDecision: Equatable {
        /// The cache sits exactly at the reusable prefix — decode the delta directly. Calling
        /// trim here would be an empty-range removal, which hybrid caches reject.
        case decodeDeltaWithoutTrim
        /// The cache holds more than the reusable prefix and this model can rewind: trim, then
        /// decode the delta.
        case trimThenDecode
        /// No usable prefix, or a rewind this model cannot perform: build a fresh sequence.
        case rebuildFresh
    }

    enum PostGenerationAction: Equatable {
        /// Remove the sampled tokens so the cache returns to prompt-only state.
        case trim
        /// Put the captured prompt-only state back; never trims, so it works on hybrid caches.
        case restoreSnapshot
    }

    /// Decision for an arriving prompt that shares `reusableTokenCount` tokens with the cache's
    /// current content of `decodedTokenCount` tokens.
    static func reuseDecision(
        modelRejectsPartialTrims: Bool,
        reusableTokenCount: Int,
        decodedTokenCount: Int
    ) -> ReuseDecision {
        guard reusableTokenCount > 0 else {
            return .rebuildFresh
        }
        if reusableTokenCount == decodedTokenCount {
            return .decodeDeltaWithoutTrim
        }
        return modelRejectsPartialTrims ? .rebuildFresh : .trimThenDecode
    }

    /// How to return the cache to prompt-only state after sampling. The trim still runs as a
    /// probe while no snapshot exists — its rejection is the signal that turns the snapshot
    /// path on for this model.
    static func postGenerationAction(
        modelRejectsPartialTrims: Bool,
        hasSnapshotForCurrentPrompt: Bool
    ) -> PostGenerationAction {
        if modelRejectsPartialTrims, hasSnapshotForCurrentPrompt {
            return .restoreSnapshot
        }
        return .trim
    }

    /// Whether capturing a sequence snapshot is worth it: only on models that cannot trim
    /// (dense models rewind for free) and only when the engine reports a sane, bounded size.
    static func shouldCaptureSnapshot(
        modelRejectsPartialTrims: Bool,
        snapshotSizeBytes: Int
    ) -> Bool {
        guard modelRejectsPartialTrims else {
            return false
        }
        return snapshotSizeBytes > 0 && snapshotSizeBytes <= maximumSnapshotBytes
    }
}

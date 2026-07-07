import Foundation

/// Decides whether an empty generation earns one seed-walked regeneration. The fixed sampler
/// seed that keeps ghost text reproducible also means an empty result reproduces exactly at the
/// same caret, so a pause the model answered with silence stays silent forever; one retry on a
/// walked seed frequently produces a real suggestion. Capped to one per content signature so
/// genuinely finished text does not regenerate in a loop at every pause. The retry is scheduled
/// as replaceable debounced work, so any newer keystroke silently cancels it.
nonisolated enum IdleRetryPolicy {
    static func shouldRetry(emptySignature: String, lastRetriedSignature: String?) -> Bool {
        emptySignature != lastRetriedSignature
    }
}

import Foundation

/// Decides whether a completed generation whose work id was superseded by a newer keystroke may
/// be recorded into `SuggestionAnchorCache` for the restore path to re-serve. The cache route is
/// deliberate: presenting the stale text directly would bypass every display guard the apply
/// path accumulated (disabled surfaces, typo gate, acceptance-echo, duplication re-checks),
/// whereas a recorded anchor is only ever served by `restoreSuggestionFromAnchorCache`, which
/// runs on the live cycle behind all of them.
///
/// Staleness must be the ONLY reason the result went unused:
/// - a cancelled task means teardown (global toggle, per-app disable, picker takeover), not typing;
/// - a speculative result's sole safe consumer is its own signature validation;
/// - secure-field text must never sit in a plain-string cache;
/// - an empty normalization has nothing to re-serve.
nonisolated enum StaleResultRescuePolicy {
    static func shouldRecord(
        isEnabled: Bool,
        isTaskCancelled: Bool,
        isSpeculative: Bool,
        isSecure: Bool,
        normalizedText: String
    ) -> Bool {
        isEnabled
            && !isTaskCancelled
            && !isSpeculative
            && !isSecure
            && !normalizedText.isEmpty
    }
}

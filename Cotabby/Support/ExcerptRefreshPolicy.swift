import Foundation

/// When a ready screen-context excerpt has gone stale for a still-focused field, decide whether
/// this moment is safe to re-capture. Staleness matters most in chat fields: the field text is
/// only the draft, so the excerpt is the model's entire view of the conversation, and one
/// captured at focus time describes minutes-old state. The idle requirement is the KV-cache
/// guard: a refresh rewrites the stable prompt head, and that rebuild must be paid during a
/// pause (where the follow-up generation doubles as the prewarm), never on a keystroke.
nonisolated enum ExcerptRefreshPolicy {
    static let minimumExcerptAgeSeconds: TimeInterval = 30
    static let minimumIdleSeconds: TimeInterval = 2

    static func shouldRefresh(excerptAgeSeconds: TimeInterval, idleSeconds: TimeInterval?) -> Bool {
        guard let idleSeconds else {
            return false
        }
        return excerptAgeSeconds >= minimumExcerptAgeSeconds
            && idleSeconds >= minimumIdleSeconds
    }
}

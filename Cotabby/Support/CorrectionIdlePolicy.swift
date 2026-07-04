import Foundation

/// Decides whether a native spell-checker correction may be presented right now or must wait for
/// the keyboard to go quiet. Corrections painted mid-burst are invalidated by the very next
/// keystroke 20-140ms later, so presenting them during fluent typing is pure flicker: the user
/// never gets to read the green text, and ghost text blinking several times per second is the
/// opposite of the calm the overlay is meant to convey. Model continuations are unaffected —
/// they have their own debounce-and-cancel lifecycle.
nonisolated enum CorrectionIdlePolicy {
    static let idleThresholdMilliseconds = 250

    /// Returns nil when the correction may be presented immediately, otherwise the number of
    /// milliseconds to wait before re-checking (via the same latest-wins debounced work used for
    /// generation scheduling, so any newer keystroke silently replaces the re-check).
    static func remainingDelayMilliseconds(
        now: Date,
        lastKeystrokeAt: Date?,
        thresholdMilliseconds: Int = idleThresholdMilliseconds
    ) -> Int? {
        guard let lastKeystrokeAt else {
            return nil
        }

        let elapsedMilliseconds = now.timeIntervalSince(lastKeystrokeAt) * 1000
        guard elapsedMilliseconds >= 0 else {
            // A keystroke stamped in the future means the clock moved under us; waiting out the
            // full window is the safe reading (never present into what may be an active burst).
            return thresholdMilliseconds
        }

        let remaining = thresholdMilliseconds - Int(elapsedMilliseconds)
        return remaining > 0 ? remaining : nil
    }
}

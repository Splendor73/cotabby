import CoreGraphics
import Foundation

/// Decides when the popup (mirror) card re-anchors to the live caret. The card holds its screen
/// position while the user types along one visual line and only moves when the caret changes
/// line. A card that follows the caret rightward on every keystroke is a moving target the eye
/// cannot track while typing fast; a stationary card the user can rest their gaze on reads far
/// better. Vertical position is the line signal: it stays constant as text is typed along a line
/// and jumps ~a line height on a line change.
nonisolated enum MirrorCardPinPolicy {
    static func shouldReanchor(
        pinnedCaretMinY: CGFloat?,
        liveCaretMinY: CGFloat,
        caretHeight: CGFloat
    ) -> Bool {
        guard let pinnedCaretMinY else { return true }
        // Half a line distinguishes a real line change from the sub-pixel wobble that
        // derived/estimated carets show on the same line; floored so a tiny/zero caret height
        // still absorbs a few points of jitter.
        let threshold = max(6, caretHeight * 0.5)
        return abs(liveCaretMinY - pinnedCaretMinY) > threshold
    }
}

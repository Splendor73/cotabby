import Foundation

/// File overview:
/// Pure recovery rules for the trailing half of the windowed Accessibility text read.
///
/// Why this file exists: Chromium/Electron contenteditables (Discord, Claude, Slack, VS Code
/// webviews) reliably answer `AXStringForRange` for the before-caret and selected ranges but
/// return nil — or a successful empty string — for the trailing range, even though the host's
/// own `AXNumberOfCharacters` proves characters follow the caret. Silently treating that answer
/// as "no trailing text" made mid-line carets look end-of-line, which let inline ghost text
/// paint on top of the user's real text instead of promoting to the mirror card
/// (`CompletionRenderModePolicy` promotes on `!isCaretAtEndOfLine`).
///
/// The resolver stays responsible for all AX I/O; these helpers only decide when the trailing
/// answer cannot be trusted and how to slice a replacement out of the full `AXValue` without
/// reading past what the host actually returned.
enum AXTrailingTextRecovery {
    /// True when the host advertises trailing characters but the parameterized read answered
    /// nothing. A successful-but-empty answer for a non-empty range is the same lie as a nil
    /// answer, so both trigger recovery.
    static func needsRecovery(afterLength: Int, nativeTrailingText: String?) -> Bool {
        guard afterLength > 0 else {
            return false
        }
        guard let nativeTrailingText else {
            return true
        }
        return nativeTrailingText.isEmpty
    }

    /// Slices the capped trailing window out of the full field value, or nil when the value is
    /// too short for the advertised range — Electron sometimes disagrees with its own
    /// `AXNumberOfCharacters`, and slicing past the real end would trap. Offsets and lengths are
    /// UTF-16 units, matching AX range semantics.
    static func slicedTrailingText(fullText: String, afterStart: Int, afterLength: Int) -> String? {
        guard afterStart >= 0, afterLength > 0 else {
            return nil
        }

        let nsText = fullText as NSString
        guard afterStart <= nsText.length - afterLength else {
            return nil
        }

        return nsText.substring(with: NSRange(location: afterStart, length: afterLength))
    }
}

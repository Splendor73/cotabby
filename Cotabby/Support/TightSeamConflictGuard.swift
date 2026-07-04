import Foundation

/// File overview:
/// Suppresses completions that compete with text already touching the caret.
///
/// Why this file exists: at a "tight seam" — the character after the caret is not whitespace —
/// the text that follows already occupies the syntactic slot a completion would fill.
/// Prefix-blind models cannot see that text and routinely invent a rival continuation:
/// "The meeting is at 3|:30 tomorrow" draws ":00 p.m.", "jane|@example.com" draws "@mail.".
/// None of those duplicate the trailing text, so `TrailingDuplicationFilter` rightly stays
/// quiet; the tell is that the completion and the trailing text begin with the same character
/// class (both word characters or both punctuation), i.e. they are two answers to one slot.
///
/// Cross-class joins stay allowed because they compose instead of competing: a word completion
/// before punctuation ("before |? it unblocks" → "standup?") reads correctly. Suppression here
/// is deliberately class-based and narrow — semantic rivalry across a whitespace boundary is
/// model-quality territory (the right-context prompt), not a filter's.
enum TightSeamConflictGuard {
    /// True when the completion opens by competing for the slot the trailing text already
    /// fills. Callers should run the duplication filter first: an exact echo is a different
    /// (and more precisely attributable) suppression.
    static func conflictsWithTrailingText(completion: String, trailingText: String) -> Bool {
        guard let trailingFirst = trailingText.unicodeScalars.first,
              let completionFirst = completion.unicodeScalars.first
        else {
            return false
        }
        guard !CharacterSet.whitespacesAndNewlines.contains(trailingFirst) else {
            return false
        }
        // A completion that opens with whitespace detaches itself from the seam; what follows
        // the space starts a new slot and no longer rivals the trailing text.
        guard !CharacterSet.whitespacesAndNewlines.contains(completionFirst) else {
            return false
        }

        return isWordish(trailingFirst) == isWordish(completionFirst)
    }

    /// Letters and digits fill word slots; every other printable character fills a
    /// punctuation/symbol slot.
    private static func isWordish(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar)
    }
}

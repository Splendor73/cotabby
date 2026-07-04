import XCTest
@testable import Cotabby

/// Pins the tight-seam conflict rule the model matrix exposed: prefix-blind models invent a
/// competing continuation for a slot the trailing text already fills — "3|:30 tomorrow" gets
/// ":00 p.m.", "jane|@example.com" gets "@mail.". None of those duplicate the trailing text, so
/// the duplication filter rightly stays quiet; the conflict is that completion and trailing text
/// begin with the same character class and therefore compete for the same syntactic slot.
final class TightSeamConflictGuardTests: XCTestCase {
    // MARK: - The eval failures this guard exists for

    func test_competingPunctuationContinuation_conflicts() {
        // "The meeting is at 3" + ":30 tomorrow..." already there; model proposed ":00 p.m."
        XCTAssertTrue(
            TightSeamConflictGuard.conflictsWithTrailingText(
                completion: ":00 p.m.",
                trailingText: ":30 tomorrow afternoon in the main conference room."
            )
        )
    }

    func test_competingEmailDomain_conflicts() {
        XCTAssertTrue(
            TightSeamConflictGuard.conflictsWithTrailingText(
                completion: "@mail.",
                trailingText: "@example.com before the end of the day."
            )
        )
    }

    func test_competingWordContinuation_conflicts() {
        // Caret mid-token before existing digits: "Suite 3|01 N. 2nd Street..." rewritten.
        XCTAssertTrue(
            TightSeamConflictGuard.conflictsWithTrailingText(
                completion: "01 N. 2nd Street, Suite 300, Phoenix, AZ 85012.",
                trailingText: "01 N. 2nd Street, Suite 300, Phoenix, AZ 85012."
            )
        )
    }

    // MARK: - Legitimate completions that must survive

    func test_wordCompletionBeforePunctuationTrailing_isAllowed() {
        // "can you review my PR before |? it unblocks..." — "standup" joins cleanly with "?".
        XCTAssertFalse(
            TightSeamConflictGuard.conflictsWithTrailingText(
                completion: "standup",
                trailingText: "? it unblocks the release branch"
            )
        )
    }

    func test_wordCompletionBeforeCommaTrailing_isAllowed() {
        // "new bookings slowed in |, so the forecast..." — "September" + "," joins cleanly.
        XCTAssertFalse(
            TightSeamConflictGuard.conflictsWithTrailingText(
                completion: "September",
                trailingText: ", so the forecast for Q4 assumes a longer sales cycle."
            )
        )
    }

    func test_whitespaceLeadingTrailing_isNeverATightSeam() {
        XCTAssertFalse(
            TightSeamConflictGuard.conflictsWithTrailingText(
                completion: "schedule a call",
                trailingText: " that we need to resolve before Friday."
            )
        )
        XCTAssertFalse(
            TightSeamConflictGuard.conflictsWithTrailingText(
                completion: ".",
                trailingText: " while we sorted this out."
            )
        )
    }

    func test_emptyTrailingOrCompletion_neverConflicts() {
        XCTAssertFalse(
            TightSeamConflictGuard.conflictsWithTrailingText(completion: "anything", trailingText: "")
        )
        XCTAssertFalse(
            TightSeamConflictGuard.conflictsWithTrailingText(completion: "", trailingText: ":30")
        )
    }

    func test_newlineLeadingTrailing_isNotATightSeam() {
        XCTAssertFalse(
            TightSeamConflictGuard.conflictsWithTrailingText(
                completion: "Thanks again for your help.",
                trailingText: "\nBest regards,\nYash"
            )
        )
    }

    // MARK: - Normalizer integration

    func test_normalizerSuppressesTightSeamConflicts() {
        let request = CotabbyTestFixtures.suggestionRequest(
            precedingText: "The meeting is at 3",
            trailingText: ":30 tomorrow afternoon in the main conference room."
        )
        let result = SuggestionTextNormalizer.normalizeDetailed(":00 p.m.", for: request)
        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.suppression, .conflictsWithTrailingText)
    }

    func test_normalizerAllowsCleanSeamJoins() {
        let request = CotabbyTestFixtures.suggestionRequest(
            precedingText: "can you review my PR before",
            trailingText: "? it unblocks the release branch"
        )
        let result = SuggestionTextNormalizer.normalizeDetailed(" standup", for: request)
        XCTAssertTrue(result.text.contains("standup"), "clean joins must survive: got \(result.text)")
        XCTAssertNil(result.suppression)
    }
}

import Foundation
import XCTest
@testable import Cotabby

/// Pins the tri-state trailing-text contract: when the resolver could not read what follows the
/// caret — but the host's own document length proves characters exist there — the snapshot must
/// say so, and end-of-line detection must answer false. That routes mid-line completions into the
/// mirror card (`CompletionRenderModePolicy` promotes on `!isCaretAtEndOfLine`) instead of letting
/// inline ghost text paint over text the app simply could not see.
final class TrailingTextReliabilityTests: XCTestCase {
    private func makeSnapshot(
        trailingText: String,
        isTrailingTextReliable: Bool
    ) -> FocusedInputSnapshot {
        FocusedInputSnapshot(
            applicationName: "TestApp",
            bundleIdentifier: "app.test",
            processIdentifier: 123,
            elementIdentifier: "field",
            role: "AXTextArea",
            subrole: nil,
            caretRect: .zero,
            inputFrameRect: nil,
            caretSource: "test",
            caretQuality: .exact,
            observedCharWidth: nil,
            precedingText: "hello ",
            trailingText: trailingText,
            selection: NSRange(location: 6, length: 0),
            isSecure: false,
            isTrailingTextReliable: isTrailingTextReliable
        )
    }

    func test_reliableEmptyTrailing_reportsEndOfLine() {
        let context = FocusedInputContext(
            snapshot: makeSnapshot(trailingText: "", isTrailingTextReliable: true),
            generation: 1
        )
        XCTAssertTrue(context.isCaretAtEndOfLine)
    }

    func test_unreliableEmptyTrailing_neverReportsEndOfLine() {
        let context = FocusedInputContext(
            snapshot: makeSnapshot(trailingText: "", isTrailingTextReliable: false),
            generation: 1
        )
        XCTAssertFalse(
            context.isCaretAtEndOfLine,
            "An unreadable trailing range must not be mistaken for an empty one"
        )
    }

    func test_reliableTrailingWithText_reportsMidLine() {
        let context = FocusedInputContext(
            snapshot: makeSnapshot(trailingText: " rest of the line.", isTrailingTextReliable: true),
            generation: 1
        )
        XCTAssertFalse(context.isCaretAtEndOfLine)
    }

    func test_defaultIsReliable_preservingExistingCallSites() {
        let snapshot = FocusedInputSnapshot(
            applicationName: "TestApp",
            bundleIdentifier: "app.test",
            processIdentifier: 123,
            elementIdentifier: "field",
            role: "AXTextArea",
            subrole: nil,
            caretRect: .zero,
            inputFrameRect: nil,
            caretSource: "test",
            caretQuality: .exact,
            observedCharWidth: nil,
            precedingText: "hello ",
            trailingText: "",
            selection: NSRange(location: 6, length: 0),
            isSecure: false
        )
        XCTAssertTrue(snapshot.isTrailingTextReliable)
    }
}

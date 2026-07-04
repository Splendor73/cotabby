import XCTest
@testable import Cotabby

/// The optimistic snapshot must reproduce, field for field, what the host is expected to publish
/// after the insert: same identity and geometry, preceding text extended by exactly the inserted
/// chunk, caret advanced by its UTF-16 length. Its content signature is the validation token the
/// speculation machinery compares against the real publish.
final class SpeculativeAcceptanceContextTests: XCTestCase {
    func testAppendsInsertionAndAdvancesCaret() {
        let base = CotabbyTestFixtures.focusedInputSnapshot(precedingText: "Hello")
        let optimistic = SpeculativeAcceptanceContext.optimisticSnapshot(after: base, inserting: " world")

        XCTAssertEqual(optimistic.precedingText, "Hello world")
        XCTAssertEqual(optimistic.selection.location, base.selection.location + " world".utf16.count)
        XCTAssertEqual(optimistic.selection.length, 0)
        XCTAssertEqual(optimistic.trailingText, base.trailingText)
        XCTAssertEqual(optimistic.elementIdentifier, base.elementIdentifier)
        XCTAssertEqual(optimistic.focusChangeSequence, base.focusChangeSequence)
    }

    func testUTF16AdvanceCountsSurrogatePairs() {
        let base = CotabbyTestFixtures.focusedInputSnapshot(precedingText: "Nice ")
        let optimistic = SpeculativeAcceptanceContext.optimisticSnapshot(after: base, inserting: "🎉🎉")
        XCTAssertEqual(optimistic.selection.location, base.selection.location + 4)
    }

    func testSignatureMatchesAnIdenticalRealPublish() {
        let base = CotabbyTestFixtures.focusedInputSnapshot(precedingText: "Hello")
        let optimistic = SpeculativeAcceptanceContext.optimisticSnapshot(after: base, inserting: " world")
        let published = CotabbyTestFixtures.focusedInputSnapshot(
            precedingText: "Hello world",
            selection: NSRange(location: optimistic.selection.location, length: 0)
        )
        XCTAssertEqual(optimistic.contentSignature, published.contentSignature)
    }

    func testSignatureDiffersWhenHostTransformedTheText() {
        let base = CotabbyTestFixtures.focusedInputSnapshot(precedingText: "Hello")
        let optimistic = SpeculativeAcceptanceContext.optimisticSnapshot(after: base, inserting: " world")
        let autocorrected = CotabbyTestFixtures.focusedInputSnapshot(precedingText: "Hello World")
        XCTAssertNotEqual(optimistic.contentSignature, autocorrected.contentSignature)
    }

    /// Identity property: inserting nothing must reproduce the snapshot EXACTLY. This is the
    /// tripwire for the silent-field-drop class of bug — the copy went through the memberwise
    /// initializer, whose defaulted parameters quietly reset any field the copy forgot
    /// (`isTrailingTextReliable` and `isWebContentField` were being reset this way, changing
    /// prompt bytes and normalizer behavior for the speculative generation in exactly the
    /// Chromium fields where those flags matter).
    func testInsertingNothingIsIdentity_noFieldSilentlyDropped() {
        let base = FocusedInputSnapshot(
            applicationName: "Claude",
            bundleIdentifier: "com.anthropic.claudefordesktop",
            processIdentifier: 77,
            elementIdentifier: "field-x",
            role: "AXTextArea",
            subrole: "AXSub",
            caretRect: CGRect(x: 1, y: 2, width: 3, height: 4),
            inputFrameRect: CGRect(x: 5, y: 6, width: 7, height: 8),
            caretSource: "derived primary",
            caretQuality: .derived,
            observedCharWidth: 7.5,
            observedContentEdges: nil,
            precedingText: "Hello ",
            trailingText: "",
            selection: NSRange(location: 6, length: 0),
            isSecure: false,
            // The two fields the old copy silently reset — deliberately non-default here.
            isTrailingTextReliable: false,
            isIntegratedTerminal: true,
            isWebContentField: true,
            focusChangeSequence: 42,
            focusedURLString: "https://example.com",
            resolvedFieldStyle: nil,
            windowTitle: "Draft",
            fieldPlaceholder: "Type here"
        )

        XCTAssertEqual(
            SpeculativeAcceptanceContext.optimisticSnapshot(after: base, inserting: ""),
            base
        )
    }
}

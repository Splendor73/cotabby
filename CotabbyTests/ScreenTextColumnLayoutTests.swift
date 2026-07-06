import CoreGraphics
import XCTest
@testable import Cotabby

/// The OCR pass used to sort every observation on screen by row, so at equal heights a sidebar
/// label and a chat line got stitched into the same sentence — live prompts showed "Settings",
/// "Daily", "merge gate" spliced mid-sentence into conversation text. Reading order must be
/// per-column: cluster observations by horizontal overlap, keep the column that carries the most
/// text (the main content), and let full-width lines (headers) join it rather than bridge
/// columns. Vision coordinates: normalized, y grows upward.
final class ScreenTextColumnLayoutTests: XCTestCase {
    private func item(
        _ text: String,
        x originX: CGFloat,
        y originY: CGFloat,
        w width: CGFloat,
        h height: CGFloat = 0.02
    ) -> ScreenTextColumnLayout.Item {
        ScreenTextColumnLayout.Item(
            text: text,
            box: CGRect(x: originX, y: originY, width: width, height: height)
        )
    }

    func testSidebarLabelsAreExcludedFromTheMainColumn() {
        let items = [
            item("Settings", x: 0.02, y: 0.80, w: 0.10),
            item("The meeting moved to Tuesday", x: 0.30, y: 0.80, w: 0.55),
            item("Daily", x: 0.02, y: 0.60, w: 0.08),
            item("so we should prepare the deck by Monday", x: 0.30, y: 0.60, w: 0.60),
            item("Drafts", x: 0.02, y: 0.40, w: 0.09)
        ]

        XCTAssertEqual(
            ScreenTextColumnLayout.dominantColumnLines(items),
            ["The meeting moved to Tuesday", "so we should prepare the deck by Monday"]
        )
    }

    func testReadingOrderIsTopToBottomWithinTheColumn() {
        let items = [
            item("second line", x: 0.3, y: 0.5, w: 0.5),
            item("first line", x: 0.3, y: 0.9, w: 0.5),
            item("third line", x: 0.3, y: 0.1, w: 0.5)
        ]

        XCTAssertEqual(
            ScreenTextColumnLayout.dominantColumnLines(items),
            ["first line", "second line", "third line"]
        )
    }

    func testSingleColumnKeepsEverything() {
        let items = [
            item("alpha", x: 0.1, y: 0.9, w: 0.8),
            item("beta", x: 0.1, y: 0.5, w: 0.7)
        ]
        XCTAssertEqual(ScreenTextColumnLayout.dominantColumnLines(items), ["alpha", "beta"])
    }

    func testFullWidthHeaderJoinsTheMainColumnInsteadOfBridgingColumns() {
        let items = [
            item("Inbox — Work", x: 0.05, y: 0.95, w: 0.90),
            item("Chats", x: 0.02, y: 0.70, w: 0.08),
            item("please send the invoice before Friday", x: 0.30, y: 0.70, w: 0.60),
            item("Files", x: 0.02, y: 0.50, w: 0.07),
            item("and copy the finance team on it", x: 0.30, y: 0.50, w: 0.55)
        ]

        XCTAssertEqual(
            ScreenTextColumnLayout.dominantColumnLines(items),
            [
                "Inbox — Work",
                "please send the invoice before Friday",
                "and copy the finance team on it"
            ]
        )
    }

    func testSameRowWithinColumnReadsLeftToRight() {
        let items = [
            item("right half", x: 0.60, y: 0.500, w: 0.25),
            item("left half", x: 0.30, y: 0.505, w: 0.25)
        ]
        XCTAssertEqual(
            ScreenTextColumnLayout.dominantColumnLines(items),
            ["left half", "right half"]
        )
    }

    func testEmptyInputYieldsEmptyOutput() {
        XCTAssertEqual(ScreenTextColumnLayout.dominantColumnLines([]), [])
    }
}

import CoreGraphics
import Foundation

/// Column-aware reading order for OCR observations. A flat by-row sort across the whole window
/// stitched sidebar labels and status chrome into the middle of conversation sentences (live
/// prompts carried "Settings" / "Daily" / "merge gate" spliced mid-sentence), which is worse
/// context than none: the model completed against word salad. Observations are clustered into
/// vertical columns by horizontal overlap; the column carrying the most text is the main
/// content, full-width lines (headers spanning several columns) join it rather than bridge
/// otherwise-separate columns, and the winning lines come back in top-to-bottom, left-to-right
/// reading order. Vision coordinates: normalized [0,1], y grows upward.
nonisolated enum ScreenTextColumnLayout {
    struct Item: Equatable {
        let text: String
        let box: CGRect
        /// Recognizer confidence, carried through so the downstream hygiene pass can keep
        /// dropping weak guesses after reordering. Not part of the layout decision.
        let confidence: Float

        init(text: String, box: CGRect, confidence: Float = 0) {
            self.text = text
            self.box = box
            self.confidence = confidence
        }
    }

    /// Lines wider than this fraction of the observed content extent are headers/full-width
    /// content: they belong WITH the main column but must not merge columns during clustering.
    private static let spanningWidthRatio: CGFloat = 0.75
    /// Two observations share a column when their x-intervals overlap by this fraction of the
    /// narrower one, or when they sit on the same row within this gap (one visual line that the
    /// recognizer split into two boxes).
    private static let overlapRatio: CGFloat = 0.4
    private static let rowToleranceY: CGFloat = 0.02
    private static let sameRowJoinGap: CGFloat = 0.1

    static func dominantColumnLines(_ items: [Item]) -> [String] {
        dominantColumn(items).map(\.text)
    }

    static func dominantColumn(_ items: [Item]) -> [Item] {
        guard !items.isEmpty else { return [] }

        let minX = items.map(\.box.minX).min() ?? 0
        let maxX = items.map(\.box.maxX).max() ?? 1
        let extent = max(0.001, maxX - minX)

        var spanning: [Item] = []
        var columnable: [Item] = []
        for item in items {
            if item.box.width / extent > Self.spanningWidthRatio {
                spanning.append(item)
            } else {
                columnable.append(item)
            }
        }

        var parent = Array(columnable.indices)
        func find(_ index: Int) -> Int {
            var index = index
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }

        for lhs in columnable.indices {
            for rhs in columnable.indices where rhs > lhs {
                let lhsBox = columnable[lhs].box
                let rhsBox = columnable[rhs].box
                let overlap = min(lhsBox.maxX, rhsBox.maxX) - max(lhsBox.minX, rhsBox.minX)
                let narrower = min(lhsBox.width, rhsBox.width)
                let sharesColumn = narrower > 0 && overlap / narrower > Self.overlapRatio
                let sameRowNeighbor = abs(lhsBox.minY - rhsBox.minY) <= Self.rowToleranceY
                    && overlap > -Self.sameRowJoinGap
                if sharesColumn || sameRowNeighbor {
                    parent[find(lhs)] = find(rhs)
                }
            }
        }

        var clusters: [Int: [Item]] = [:]
        for index in columnable.indices {
            clusters[find(index), default: []].append(columnable[index])
        }
        let dominant = clusters.values.max { lhs, rhs in
            lhs.reduce(0) { $0 + $1.text.count } < rhs.reduce(0) { $0 + $1.text.count }
        } ?? []

        return (dominant + spanning)
            .sorted {
                if abs($0.box.minY - $1.box.minY) > Self.rowToleranceY {
                    return $0.box.minY > $1.box.minY
                }
                return $0.box.minX < $1.box.minX
            }
    }
}

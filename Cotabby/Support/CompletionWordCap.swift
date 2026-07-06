import Foundation

/// Hard word-count cap for normalized completions. The user's length setting was previously
/// prompt guidance only ("Return only the next 4 to 7 words.") — small local models overrun it
/// freely, and an over-long ghost line is slower to decode, slower to read, and harder to trust
/// at a glance. Trimming keeps the first `maxWords` whitespace-delimited runs and preserves the
/// original spacing and punctuation of everything kept (a rebuilt join would silently reflow
/// doubled spaces or attached punctuation).
nonisolated enum CompletionWordCap {
    static func trim(_ text: String, maxWords: Int) -> String {
        guard maxWords > 0 else {
            return text
        }

        var wordCount = 0
        var previousWasWhitespace = true
        for index in text.indices {
            let isWhitespace = text[index].isWhitespace
            if !isWhitespace, previousWasWhitespace {
                wordCount += 1
                if wordCount > maxWords {
                    // Cut at the start of word maxWords+1; drop the separator run before it.
                    var cut = text[..<index]
                    while let last = cut.last, last.isWhitespace {
                        cut.removeLast()
                    }
                    return String(cut)
                }
            }
            previousWasWhitespace = isWhitespace
        }
        return text
    }
}

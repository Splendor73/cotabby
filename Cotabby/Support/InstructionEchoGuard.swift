import Foundation

/// Suppresses a completion that regurgitates the user's injected writing instructions. Injecting
/// those instructions into the base-continuation prompt lengthens and shapes real completions
/// (measured), but on degenerate input (gibberish, empty field) the base model has nothing to
/// continue and echoes its conditioning preface — which would paste the instructions into the
/// document. This is the safety net that makes instruction injection shippable on the base path
/// (the instruct-format prompt is the deeper fix; this guards the base path meanwhile).
///
/// Detection is a shared run of `minWords` consecutive words (case- and punctuation-insensitive):
/// a real completion virtually never reproduces five consecutive words of the instruction, while
/// an echo reproduces many.
nonisolated enum InstructionEchoGuard {
    static func echoesInstruction(_ completion: String, instruction: String?, minWords: Int = 5) -> Bool {
        guard let instruction, !instruction.isEmpty else { return false }
        let completionWords = words(completion)
        guard completionWords.count >= minWords else { return false }
        let instructionWords = words(instruction)
        guard instructionWords.count >= minWords else { return false }

        let head = Array(completionWords.prefix(minWords))
        // Does the completion's opening run appear as a contiguous window anywhere in the
        // instruction? An echo — verbatim or from mid-instruction — starts with such a run.
        for start in 0 ... (instructionWords.count - minWords) where
            Array(instructionWords[start ..< start + minWords]) == head {
            return true
        }
        return false
    }

    private static func words(_ text: String) -> [String] {
        // Drop apostrophes first (don't treat them as separators) so "I'm" and "Im" tokenize
        // alike; then split on any other non-alphanumeric run.
        text.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}

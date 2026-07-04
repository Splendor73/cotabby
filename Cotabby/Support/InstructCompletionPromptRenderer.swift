import Foundation

/// File overview:
/// Renders the ChatML prompt for instruct-tuned catalog models (see `PromptStyle.instruct`).
///
/// Design: unlike the base renderer — which can only *condition* a raw checkpoint — an instruct
/// model has a real instruction channel, so persona, rules, length, and language become directives
/// in the system turn, and the right-context the base path cannot carry becomes an explicit
/// "text after the caret, do not repeat it" section. Byte layout is dictated by llama KV prefix
/// reuse: every stable section (system turn, surface/clipboard/screen context, the per-session
/// frozen suffix) precedes the growing caret prefix, which is the last variable bytes of the
/// prompt; only the constant turn-closing tail after it re-decodes on each request.
///
/// The ChatML template is deliberately hardcoded and selected per catalog filename via
/// `RuntimeModelProfile.promptStyle` — never guessed for unknown GGUFs, where a wrong template
/// reads as scaffolding leakage in the ghost text.
enum InstructCompletionPromptRenderer {
    /// Character budget matching the base renderer's; the token budget (when provided) supersedes.
    static let defaultContextBudget = 2400

    static func prompt(
        prefixText: String,
        suffixText: String = "",
        applicationName: String,
        userName: String?,
        customRules: [String] = [],
        extendedContext: String? = nil,
        languageInstruction: String? = nil,
        clipboardContext: String? = nil,
        visualContextSummary: String? = nil,
        surfaceContext: SurfaceContext? = nil,
        completionLengthInstruction: String,
        contextBudget: Int = defaultContextBudget,
        tokenBudget: Int? = nil
    ) -> String {
        let trimmedPrefix = BaseCompletionPromptRenderer.trimmingTrailingWhitespace(prefixText)
        let kept = budgetedSections(
            trimmedPrefix: trimmedPrefix,
            suffixText: suffixText,
            extendedContext: extendedContext,
            clipboardContext: clipboardContext,
            visualContextSummary: visualContextSummary,
            surfaceContext: surfaceContext,
            contextBudget: contextBudget,
            tokenBudget: tokenBudget
        )
        func keptContent(_ name: String) -> String? {
            kept.first { $0.name == name }?.content
        }

        let systemTurn = systemLines(
            applicationName: applicationName,
            userName: userName,
            customRules: customRules,
            languageInstruction: languageInstruction,
            completionLengthInstruction: completionLengthInstruction,
            keptNotes: keptContent("notes")
        )
        let userTurn = userLines(
            surface: keptContent("surface"),
            clipboard: keptContent("clipboard"),
            screen: keptContent("screen"),
            suffix: keptContent("suffix")
        )

        // The prefix is appended without a trailing newline so it stays the final variable bytes,
        // immediately followed by the constant tail (see the KV layout note in the file overview).
        return "<|im_start|>system\n"
            + systemTurn.joined(separator: "\n")
            + "<|im_end|>\n<|im_start|>user\n"
            + userTurn.joined(separator: "\n")
            + "\n"
            + (keptContent("prefix") ?? trimmedPrefix)
            + "<|im_end|>\n<|im_start|>assistant\n"
    }

    /// Variable-size content competes for the budget exactly like the base render: the prefix
    /// holds top priority with a guaranteed minimum, the suffix outranks ambient context
    /// (it prevents repetition errors), and everything else fills what remains.
    private static func budgetedSections(
        trimmedPrefix: String,
        suffixText: String,
        extendedContext: String? = nil,
        clipboardContext: String? = nil,
        visualContextSummary: String? = nil,
        surfaceContext: SurfaceContext? = nil,
        contextBudget: Int = defaultContextBudget,
        tokenBudget: Int? = nil
    ) -> [PromptSection] {
        var sections: [PromptSection] = []
        if let surface = surfaceContext {
            let lines = SurfaceContextComposer.prefaceLines(for: surface)
            if !lines.isEmpty {
                sections.append(contextSection("surface", lines.joined(separator: " "), priority: 70, maxChars: 240))
            }
        }
        let trimmedSuffix = suffixText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSuffix.isEmpty {
            sections.append(contextSection("suffix", trimmedSuffix, priority: 75, maxChars: 400))
        }
        if let notes = nonEmpty(extendedContext) {
            sections.append(contextSection("notes", notes, priority: 40, maxChars: 1300))
        }
        if let clip = nonEmpty(clipboardContext) {
            sections.append(contextSection("clipboard", clip, priority: 35, maxChars: 400))
        }
        if let screen = nonEmpty(visualContextSummary) {
            sections.append(contextSection("screen", screen, priority: 30, maxChars: 500))
        }
        sections.append(
            PromptSection(
                name: "prefix",
                content: trimmedPrefix,
                priority: 100,
                minChars: 1,
                maxChars: max(1, trimmedPrefix.count),
                truncation: .preserveEnd
            )
        )

        if let tokenBudget {
            return PromptSectionBudget.allocate(sections, totalTokens: tokenBudget, estimate: TokenCountEstimator.estimate)
        }
        return PromptSectionBudget.allocate(sections, totalChars: contextBudget)
    }

    /// The instruction channel: directives an instruct model actually obeys, unlike the base
    /// renderer's passive conditioning preface.
    private static func systemLines(
        applicationName: String,
        userName: String?,
        customRules: [String],
        languageInstruction: String? = nil,
        completionLengthInstruction: String,
        keptNotes: String? = nil
    ) -> [String] {
        var lines: [String] = [
            "You are an inline autocomplete engine inside \(applicationName).",
            "Continue the user's text exactly from where it stops.",
            "Output only the continuation itself: no preamble, no quotes, never repeat any of the user's text.",
            // The instruct path's unique lever over base checkpoints: it can be told to go
            // silent. Base models treat every prompt as text to extend; this line is what lets
            // the eval's negative cases (gibberish, finished thoughts, slots already filled by
            // the text after the caret) end in suppression instead of a wrong show.
            "If the text does not invite a continuation — gibberish, a finished thought, or "
                + "content whose next words already exist after the caret — output nothing at all.",
            completionLengthInstruction
        ]
        if let language = nonEmpty(languageInstruction) {
            lines.append(language)
        }
        if let name = nonEmpty(userName) {
            lines.append("Write in the voice of \(name).")
        }
        let rules = customRules
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !rules.isEmpty {
            lines.append("Style preferences: \(rules.joined(separator: ", ")).")
        }
        if let keptNotes {
            lines.append("Background the writer keeps in mind: \(keptNotes)")
        }
        return lines
    }

    private static func userLines(
        surface: String?,
        clipboard: String?,
        screen: String?,
        suffix: String?
    ) -> [String] {
        var lines: [String] = []
        if let surface {
            lines.append(surface)
        }
        if let clipboard {
            lines.append("On the clipboard: \(clipboard)")
        }
        if let screen {
            lines.append("Nearby on screen: \(screen)")
        }
        if let suffix {
            lines.append("Text after the caret (do not repeat it):\n\(suffix)")
        }
        lines.append("Continue this text:")
        return lines
    }

    private static func contextSection(
        _ name: String,
        _ content: String,
        priority: Int,
        maxChars: Int
    ) -> PromptSection {
        PromptSection(name: name, content: content, priority: priority, minChars: 0, maxChars: maxChars, truncation: .preserveStart)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

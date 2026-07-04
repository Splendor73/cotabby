import XCTest
@testable import Cotabby

/// Pins the instruct prompt's shape: a ChatML render for chat-template catalog models where every
/// stable byte (system turn, context, suffix) precedes the growing caret prefix, so llama KV
/// prefix reuse keeps amortizing them; only the short constant tail after the prefix re-decodes
/// per request. The suffix section is the right-context the base renderer cannot carry: the model
/// finally sees what follows the caret and is told not to repeat it.
final class InstructCompletionPromptRendererTests: XCTestCase {
    private func render(
        prefixText: String = "The meeting moved to",
        suffixText: String = "",
        lengthInstruction: String = "Continue with 4 to 7 words.",
        tokenBudget: Int? = nil
    ) -> String {
        InstructCompletionPromptRenderer.prompt(
            prefixText: prefixText,
            suffixText: suffixText,
            applicationName: "Mail",
            userName: "Yash",
            customRules: ["Use British spelling"],
            completionLengthInstruction: lengthInstruction,
            tokenBudget: tokenBudget
        )
    }

    func test_promptEndsWithOpenAssistantTurn() {
        XCTAssertTrue(render().hasSuffix("<|im_start|>assistant\n"))
    }

    func test_prefixIsTheFinalUserBytes_beforeTheConstantTail() {
        // KV reuse invariant: the growing caret prefix must be the last variable bytes; only the
        // fixed turn-closing tail may follow it.
        let prompt = render(prefixText: "The meeting moved to")
        XCTAssertTrue(prompt.contains("The meeting moved to<|im_end|>\n<|im_start|>assistant\n"))
    }

    func test_suffixSectionPrecedesThePrefix_andForbidsRepetition() {
        let prompt = render(
            prefixText: "The deployment failed because the",
            suffixText: " was misconfigured in staging."
        )
        let suffixMarker = try? XCTUnwrap(prompt.range(of: "Text after the caret"))
        let prefixRange = try? XCTUnwrap(prompt.range(of: "The deployment failed because the"))
        guard let suffixMarker, let prefixRange else { return }
        XCTAssertLessThan(
            suffixMarker.lowerBound, prefixRange.lowerBound,
            "suffix bytes are frozen per session and must precede the growing prefix"
        )
        XCTAssertTrue(prompt.contains("do not repeat"))
        XCTAssertTrue(prompt.contains("was misconfigured in staging."))
    }

    func test_emptySuffixOmitsTheSection() {
        XCTAssertFalse(render(suffixText: "").contains("Text after the caret"))
    }

    func test_systemTurnCarriesRulesAndLength() {
        let prompt = render()
        let systemTurn = prompt.components(separatedBy: "<|im_end|>").first ?? ""
        XCTAssertTrue(systemTurn.contains("<|im_start|>system"))
        XCTAssertTrue(systemTurn.contains("Use British spelling"))
        XCTAssertTrue(systemTurn.contains("Continue with 4 to 7 words."))
    }

    func test_systemTurnTeachesSuppression() {
        // The instruct model's unique lever over the base catalog: it can be TOLD to go silent.
        // The eval's negative cases (gibberish, finished thoughts, content already present after
        // the caret) are the metric; only a model with an instruction channel can act on this.
        let systemTurn = render().components(separatedBy: "<|im_end|>").first ?? ""
        XCTAssertTrue(
            systemTurn.contains("output nothing"),
            "the suppression rule must live in the system turn"
        )
    }

    func test_tightTokenBudgetKeepsTheEndOfThePrefix() {
        let head = "HEADHEADHEAD "
        let tail = "the caret is right here"
        let prompt = render(
            prefixText: head + String(repeating: "filler words keep coming ", count: 400) + tail,
            tokenBudget: 160
        )
        XCTAssertTrue(prompt.contains(tail), "the bytes nearest the caret must survive truncation")
        XCTAssertFalse(prompt.contains(head), "the far end of a huge prefix is what gets cut")
    }
}

/// Pins renderer selection: only catalog models whose profile declares the instruct style get the
/// ChatML render; base models and unknown user GGUFs stay on the conservative base continuation.
final class PromptStyleSelectionTests: XCTestCase {
    func test_instructModelProfileDeclaresInstructStyle() {
        XCTAssertEqual(
            RuntimeModelCatalog.profile(for: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf")?.promptStyle,
            .instruct
        )
    }

    private func makeContext(trailingText: String, isTrailingTextReliable: Bool) -> FocusedInputContext {
        FocusedInputContext(
            snapshot: FocusedInputSnapshot(
                applicationName: "Mail",
                bundleIdentifier: "com.apple.mail",
                processIdentifier: 1,
                elementIdentifier: "field",
                role: "AXTextArea",
                subrole: nil,
                caretRect: .zero,
                inputFrameRect: nil,
                caretSource: "test",
                caretQuality: .exact,
                observedCharWidth: nil,
                precedingText: "Hello team, the plan for",
                trailingText: trailingText,
                selection: NSRange(location: 24, length: 0),
                isSecure: false,
                isTrailingTextReliable: isTrailingTextReliable
            ),
            generation: 1
        )
    }

    private func buildPrompt(promptStyle: PromptStyle, trailingText: String = "", reliable: Bool = true) -> String {
        SuggestionRequestFactory.buildRequest(
            context: makeContext(trailingText: trailingText, isTrailingTextReliable: reliable),
            settings: CotabbyTestFixtures.settingsSnapshot(selectedEngine: .llamaOpenSource),
            configuration: .standard,
            promptStyle: promptStyle
        ).request.prompt
    }

    func test_instructStyleRendersChatTemplate() {
        XCTAssertTrue(buildPrompt(promptStyle: .instruct).contains("<|im_start|>system"))
    }

    func test_baseStyleKeepsTheBareContinuationPrompt() {
        XCTAssertFalse(buildPrompt(promptStyle: .baseContinuation).contains("<|im_start|>"))
    }

    func test_instructStyleCarriesReliableTrailingTextAsSuffix() {
        let prompt = buildPrompt(promptStyle: .instruct, trailingText: " next week is unchanged.")
        XCTAssertTrue(prompt.contains("Text after the caret"))
        XCTAssertTrue(prompt.contains("next week is unchanged."))
    }

    func test_instructStyleDropsUnreadableTrailingText() {
        // A2's tri-state: an unreadable trailing range must not be injected as if it were real.
        let prompt = buildPrompt(promptStyle: .instruct, trailingText: "", reliable: false)
        XCTAssertFalse(prompt.contains("Text after the caret"))
    }
}

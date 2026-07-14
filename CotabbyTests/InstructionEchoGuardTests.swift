import XCTest
@testable import Cotabby

/// A base-continuation model, given the user's writing instructions as conditioning context, will
/// on degenerate input (gibberish, empty) just continue the preface — regurgitating the
/// instructions into the field. The guard detects that echo by a shared run of consecutive words
/// and suppresses it, so injecting instructions (which lengthens real completions) can't paste the
/// instruction text into the user's document.
final class InstructionEchoGuardTests: XCTestCase {
    private let instruction = "I'm a student, and I mostly use this for project writeups, report "
        + "sections, README text, and short technical explanations. Write in first person."

    func testVerbatimEchoIsCaught() {
        XCTAssertTrue(InstructionEchoGuard.echoesInstruction(
            "I'm a student, and I mostly use this for project writeups",
            instruction: instruction))
    }

    func testEchoFromMidInstructionIsCaught() {
        XCTAssertTrue(InstructionEchoGuard.echoesInstruction(
            "report sections, README text, and short technical explanations",
            instruction: instruction))
    }

    func testNormalCompletionIsNotCaught() {
        XCTAssertFalse(InstructionEchoGuard.echoesInstruction(
            "the meeting has been moved to Tuesday afternoon",
            instruction: instruction))
    }

    func testShortCompletionCannotFalseMatch() {
        // Fewer than the required run of words — cannot be judged an echo.
        XCTAssertFalse(InstructionEchoGuard.echoesInstruction("I'm a student", instruction: instruction))
    }

    func testNilOrEmptyInstructionNeverEchoes() {
        XCTAssertFalse(InstructionEchoGuard.echoesInstruction("anything at all here", instruction: nil))
        XCTAssertFalse(InstructionEchoGuard.echoesInstruction("anything at all here", instruction: ""))
    }

    func testCaseAndPunctuationInsensitive() {
        XCTAssertTrue(InstructionEchoGuard.echoesInstruction(
            "IM A STUDENT AND I MOSTLY USE",
            instruction: instruction))
    }
}

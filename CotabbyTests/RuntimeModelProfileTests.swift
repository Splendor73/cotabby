import XCTest
@testable import Cotabby

/// Pins the per-model runtime profile: which catalog models override the global runtime
/// configuration, and how the llama prompt token budget follows the *loaded* context window
/// instead of the compile-time default (the old static coupling under-filled any model whose
/// window differs from 2048).
final class RuntimeModelProfileTests: XCTestCase {
    func test_instructModelProfile_raisesContextWindow() {
        let profile = RuntimeModelCatalog.profile(for: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf")
        XCTAssertEqual(profile?.contextWindowTokens, 4096)
    }

    func test_hybridCatalogModels_haveNoProfile() {
        // The hybrid/SWA base models keep the global default; a profile exists only where a
        // deliberate, evaluated decision overrides it.
        for filename in [
            "Qwen3.5-0.8B-Base.i1-Q6_K.gguf",
            "Qwen3.5-2B-Base.i1-Q4_K_M.gguf",
            "gemma-4-E2B.i1-Q6_K.gguf",
            "gemma-4-E4B.i1-Q4_K_M.gguf"
        ] {
            XCTAssertNil(RuntimeModelCatalog.profile(for: filename), filename)
        }
        XCTAssertNil(RuntimeModelCatalog.profile(for: "user-supplied-custom.gguf"))
    }

    func test_effectiveConfiguration_overridesOnlyProfiledFields() {
        let base = LlamaRuntimeConfiguration.default
        let effective = RuntimeModelCatalog.effectiveConfiguration(
            base, forModelFilename: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
        )

        XCTAssertEqual(effective.contextWindowTokens, 4096)
        XCTAssertEqual(effective.batchSize, base.batchSize)
        XCTAssertEqual(effective.gpuLayerCount, base.gpuLayerCount)
        XCTAssertEqual(effective.preferredModelNames, base.preferredModelNames)
        XCTAssertEqual(effective.runtimeDirectoryPath, base.runtimeDirectoryPath)
    }

    func test_effectiveConfiguration_isIdentityForUnprofiledModels() {
        let base = LlamaRuntimeConfiguration.default
        XCTAssertEqual(
            RuntimeModelCatalog.effectiveConfiguration(base, forModelFilename: "gemma-4-E2B.i1-Q6_K.gguf"),
            base
        )
        XCTAssertEqual(RuntimeModelCatalog.effectiveConfiguration(base, forModelFilename: nil), base)
    }

    func test_promptTokenBudget_followsTheGivenContextWindow() {
        XCTAssertEqual(
            SuggestionConfiguration.llamaPromptTokenBudget(forContextWindowTokens: 4096),
            4096
                - SuggestionConfiguration.llamaPromptOutputCeilingTokens
                - SuggestionConfiguration.llamaPromptSafetyMarginTokens
        )
        // At the global default window the parameterized formula and the shipped static value
        // must agree, so threading the loaded window through changes nothing on catalog models.
        XCTAssertEqual(
            SuggestionConfiguration.llamaPromptTokenBudget(
                forContextWindowTokens: LlamaRuntimeConfiguration.default.contextWindowTokens
            ),
            SuggestionConfiguration.derivedLlamaPromptTokenBudget
        )
    }
}

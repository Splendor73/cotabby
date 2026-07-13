import Foundation

/// File overview:
/// Shared value types for runtime bootstrap, model selection, diagnostics, and runtime errors.
/// These types keep runtime state serializable, testable, and separate from the service layer.
///
/// Human-readable lifecycle states surfaced to the UI during runtime bootstrap.
enum RuntimeBootstrapState: Equatable, Sendable {
    case idle
    case starting(String)
    case loading(String)
    case ready(String)
    case failed(String)

    var summary: String {
        switch self {
        case .idle:
            return "Idle"
        case .starting(let detail),
            .loading(let detail),
            .ready(let detail),
            .failed(let detail):
            return detail
        }
    }

    /// Convenience accessor for callers that only care about the failed case (e.g. the Settings
    /// sidebar's attention evaluator). Returns `nil` for healthy states so the call site stays a
    /// single `if let` rather than a multi-case switch.
    var failureDetail: String? {
        if case .failed(let detail) = self {
            return detail
        }
        return nil
    }
}

/// One discovered GGUF model option that can be displayed in the menu and loaded at runtime.
/// Known built-in filenames are mapped to product-facing aliases, while unknown custom uploads
/// intentionally fall back to their raw filename so user-provided models stay selectable.
struct RuntimeModelOption: Equatable, Hashable, Sendable, Identifiable {
    let filename: String
    let url: URL

    var id: String { filename }
    var displayName: String { RuntimeModelCatalog.displayName(for: filename) }
    var actualModelName: String { filename }
}

/// Downloadable model metadata used by onboarding and menu-based model installation.
/// Keeping this as app-level data lets us update app code and model artifacts independently.
struct DownloadableRuntimeModel: Equatable, Hashable, Sendable, Identifiable {
    let filename: String
    let displayName: String
    let downloadURL: URL
    let approximateSizeInGigabytes: Double
    /// Exact byte count of the served file. Optional so future catalog entries
    /// can land while metadata is still being filled in. When non-nil, the
    /// download manager runs `ModelFileValidator.validateSize` against it
    /// before promoting the staged file into the install location.
    let expectedSizeBytes: Int64?
    /// Lowercase SHA-256 hex string for the served file. Same nullability
    /// rationale as `expectedSizeBytes`. HuggingFace exposes this as the
    /// `x-linked-etag` response header on its CDN URLs.
    let sha256: String?
    let alternateFilenames: [String]

    var id: String { filename }
    var actualModelName: String { filename }
    var approximateSizeLabel: String { String(format: "~%.1f GB", approximateSizeInGigabytes) }

    var allKnownFilenames: [String] {
        [filename] + alternateFilenames
    }

    init(
        filename: String,
        displayName: String,
        downloadURL: URL,
        approximateSizeInGigabytes: Double,
        expectedSizeBytes: Int64? = nil,
        sha256: String? = nil,
        alternateFilenames: [String] = []
    ) {
        self.filename = filename
        self.displayName = displayName
        self.downloadURL = downloadURL
        self.approximateSizeInGigabytes = approximateSizeInGigabytes
        self.expectedSizeBytes = expectedSizeBytes
        self.sha256 = sha256
        self.alternateFilenames = alternateFilenames
    }
}

/// How the llama prompt is rendered for a model: bare continuation for base checkpoints, a chat
/// template for instruct checkpoints. Unknown user-supplied GGUFs default to `.baseContinuation`
/// — the conservative renderer that cannot leak template scaffolding a model was never trained on.
enum PromptStyle: Equatable, Sendable {
    case baseContinuation
    case instruct
}

/// Per-model overrides of the global runtime configuration. Keyed by GGUF filename in
/// `RuntimeModelCatalog.profiles`; absent fields (and absent profiles) fall through to
/// `LlamaRuntimeConfiguration`'s values, so unknown user-supplied models keep today's behavior.
/// Grows with later stages (sampling); kept minimal until each field has an evaluated reason to
/// exist.
struct RuntimeModelProfile: Equatable, Sendable {
    /// Per-sequence KV capacity to load this model with. Only profiled models pay the larger
    /// cache; the hybrid/SWA catalog models keep the global default.
    var contextWindowTokens: Int32?
    /// Prompt render for this model. Templates are scoped to catalog-listed filenames only —
    /// never guessed for unknown models, where a wrong template reads as scaffolding leakage.
    var promptStyle: PromptStyle = .baseContinuation
    /// Per-model sampling overrides. Nil fields fall through to `SuggestionConfiguration`'s
    /// global tuning (which was swept for the base catalog); values land here only after an
    /// eval-matrix comparison, never from a model card alone.
    var temperature: Double?
    var topK: Int?
    var topP: Double?
    var minP: Double?
}

enum RuntimeModelCatalog {
    /// The deliberate per-model overrides. A model earns an entry here through measurement, not
    /// by existing: the instruct model's 4096 window is affordable because its dense KV cache
    /// supports prefix reuse (the window prefills once per field, not once per keystroke).
    private static let profiles: [String: RuntimeModelProfile] = [
        "Qwen3-4B-Instruct-2507-Q4_K_M.gguf": RuntimeModelProfile(
            contextWindowTokens: 4096,
            promptStyle: .instruct
        )
    ]

    static func profile(for filename: String?) -> RuntimeModelProfile? {
        filename.flatMap { profiles[$0] }
    }

    /// The configuration a specific model should actually load with: the global configuration
    /// with any profiled fields overridden. Identity for unprofiled models.
    static func effectiveConfiguration(
        _ configuration: LlamaRuntimeConfiguration,
        forModelFilename filename: String?
    ) -> LlamaRuntimeConfiguration {
        guard let profile = profile(for: filename) else {
            return configuration
        }

        return LlamaRuntimeConfiguration(
            runtimeDirectoryPath: configuration.runtimeDirectoryPath,
            preferredModelNames: configuration.preferredModelNames,
            contextWindowTokens: profile.contextWindowTokens ?? configuration.contextWindowTokens,
            batchSize: configuration.batchSize,
            gpuLayerCount: configuration.gpuLayerCount
        )
    }

    static func displayName(for filename: String) -> String {
        switch filename {
        case "Qwen3.5-0.8B-Base.i1-Q6_K.gguf":
            return "tabby-2-nano"
        case "Qwen3.5-2B-Base.i1-Q4_K_M.gguf":
            return "tabby-2-mini"
        case "gemma-4-E2B.i1-Q6_K.gguf":
            return "tabby-2-base"
        case "gemma-4-E4B.i1-Q4_K_M.gguf":
            return "tabby-2-pro"
        case "Qwen3-4B-Instruct-2507-Q4_K_M.gguf":
            return "tabby-2-swift"
        default:
            return filename
        }
    }

    /// Builds a HuggingFace direct-download URL from a repo and file path.
    private static func hfURL(_ repo: String, _ file: String) -> URL {
        // Force-unwrap is safe: inputs are compile-time literals forming a valid URL.
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file)?download=true")!
    }

    /// Canonical downloadable base GGUF models for Cotabby 2's base-model continuation path.
    /// Qwen3.5 / Gemma base checkpoints from mradermacher's i1 GGUF repos. `expectedSizeBytes` and
    /// `sha256` stay nil pending CDN-header capture; the download manager skips size/hash
    /// validation when they are nil. Old instruct GGUFs are intentionally no longer listed.
    static let downloadableModels: [DownloadableRuntimeModel] = [
        DownloadableRuntimeModel(
            filename: "Qwen3.5-0.8B-Base.i1-Q6_K.gguf",
            displayName: displayName(for: "Qwen3.5-0.8B-Base.i1-Q6_K.gguf"),
            downloadURL: hfURL("mradermacher/Qwen3.5-0.8B-Base-i1-GGUF", "Qwen3.5-0.8B-Base.i1-Q6_K.gguf"),
            approximateSizeInGigabytes: 0.8
        ),
        DownloadableRuntimeModel(
            filename: "Qwen3.5-2B-Base.i1-Q4_K_M.gguf",
            displayName: displayName(for: "Qwen3.5-2B-Base.i1-Q4_K_M.gguf"),
            downloadURL: hfURL("mradermacher/Qwen3.5-2B-Base-i1-GGUF", "Qwen3.5-2B-Base.i1-Q4_K_M.gguf"),
            approximateSizeInGigabytes: 1.4
        ),
        DownloadableRuntimeModel(
            filename: "gemma-4-E2B.i1-Q6_K.gguf",
            displayName: displayName(for: "gemma-4-E2B.i1-Q6_K.gguf"),
            downloadURL: hfURL("mradermacher/gemma-4-E2B-i1-GGUF", "gemma-4-E2B.i1-Q6_K.gguf"),
            approximateSizeInGigabytes: 4.5
        ),
        DownloadableRuntimeModel(
            filename: "gemma-4-E4B.i1-Q4_K_M.gguf",
            displayName: displayName(for: "gemma-4-E4B.i1-Q4_K_M.gguf"),
            downloadURL: hfURL("mradermacher/gemma-4-E4B-i1-GGUF", "gemma-4-E4B.i1-Q4_K_M.gguf"),
            approximateSizeInGigabytes: 5.0
        ),
        // Dense-attention instruct model (Apache-2.0). Unlike the hybrid/SWA base catalog above,
        // its KV cache accepts partial trims, which revives prefix reuse and prewarm: requests
        // decode only the typed delta instead of re-prefilling the whole prompt (see
        // `LlamaRuntimeCore.trimKV`). Deliberately absent from the default preferred order until
        // eval numbers justify the flip; size+hash captured from the CDN headers (x-linked-size /
        // x-linked-etag, 2026-07-03) so download validation runs for the first time.
        DownloadableRuntimeModel(
            filename: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
            displayName: displayName(for: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf"),
            downloadURL: hfURL("unsloth/Qwen3-4B-Instruct-2507-GGUF", "Qwen3-4B-Instruct-2507-Q4_K_M.gguf"),
            approximateSizeInGigabytes: 2.5,
            expectedSizeBytes: 2_497_281_120,
            sha256: "3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597"
        )
    ]
}

/// Startup configuration that controls which GGUF model to load and how large the runtime should be.
struct LlamaRuntimeConfiguration: Equatable, Sendable {
    let runtimeDirectoryPath: String?
    let preferredModelNames: [String]
    let contextWindowTokens: Int32
    /// `var` for exactly one writer: the dev-only `cotabbyBatchSizeOverride` A/B knob applied in
    /// `LlamaRuntimeManager.prepare` — production code treats this as immutable.
    var batchSize: Int32
    let gpuLayerCount: Int32

    /// Order matters here: the locator picks the first GGUF that exists.
    /// This list defines priority for known models; user-added GGUF files are still discoverable.
    static let `default` = LlamaRuntimeConfiguration(
        runtimeDirectoryPath: nil,
        preferredModelNames: [
            "gemma-4-E2B.i1-Q6_K.gguf",
            "Qwen3.5-2B-Base.i1-Q4_K_M.gguf",
            "Qwen3.5-0.8B-Base.i1-Q6_K.gguf",
            "gemma-4-E4B.i1-Q4_K_M.gguf"
        ],
        contextWindowTokens: 2048,
        // The prefill batch is also the cancellation granularity: the engine abort can only land
        // between chunks, so a 512-token batch made a whole ~200-token autocomplete prompt one
        // uninterruptible gulp (~250ms of dead occupancy per superseded generation). 128 keeps
        // prefill throughput within noise at these prompt sizes while quartering the abort
        // blind spot — measured as the residual latency-tail contributor after the queued-cancel
        // entry guard landed (docs/bench/2026-07-04-model-decision.md, latency-tail round).
        batchSize: 128,
        gpuLayerCount: -1
    )
}

/// Sampling and length controls for one llama generation request.
///
/// These values travel together from the suggestion layer to the runtime. Modeling them as one
/// value object keeps runtime APIs small and makes cache invalidation easier to reason about:
/// changing any option means the request belongs to a different sampling configuration.
struct LlamaGenerationOptions: Equatable, Sendable {
    let maxPredictionTokens: Int
    let temperature: Double
    let topK: Int
    let topP: Double
    let minP: Double
    let repetitionPenalty: Double
    var seed: UInt32?

    /// Masks line-break tokens so single-line fields never receive a multi-line completion.
    var singleLine: Bool = false
    /// Constrains the first generated token to continue the current word (mid-word carets only).
    var forceWordContinuation: Bool = false

    /// Average per-token log-probability below which a completion is suppressed as low-confidence.
    /// Defaults to -infinity, which disables suppression entirely.
    var confidenceFloor: Double = -.infinity

    /// Minimum tokens generated before the sentence-boundary early stop may fire. Guards against
    /// degenerate instant stops (e.g. a lone leading period). Lives here so length presets can tune
    /// the floor without reaching into `DecodeStopPolicy`; the default preserves prior behavior.
    var sentenceStopMinimumTokens: Int = 2

    /// Stop decoding the moment the raw distribution's most-likely next token is end-of-generation,
    /// even when the stochastic sampler drew something else. The model's top choice being "stop"
    /// is the strongest anti-rambling signal available per token, and the engine computes it while
    /// the logits row is hot, so honoring it costs nothing here.
    var stopAtArgmaxEOG: Bool = true
}

/// One generation's text plus the confidence signals the caller needs for suppression accounting.
/// Returned instead of a bare string so a confidence-suppressed completion is attributed to the
/// real reason rather than reading as "the model produced nothing".
struct LlamaGenerationOutput: Equatable, Sendable {
    let text: String
    /// Mean per-token log-probability of the generated tokens; nil when confidence gating was off
    /// (the engine skips the per-token logprob work entirely) or nothing was generated.
    let averageLogprob: Double?
    /// True when the completion was withheld because `averageLogprob` fell below the floor.
    let suppressedByLowConfidence: Bool

    static func text(_ text: String) -> LlamaGenerationOutput {
        LlamaGenerationOutput(text: text, averageLogprob: nil, suppressedByLowConfidence: false)
    }
}

/// The concrete runtime assets selected during bootstrap after checking available model files.
struct ResolvedLlamaRuntime: Equatable, Sendable {
    let runtimeDirectoryURL: URL
    let modelFileURL: URL
    let modelDisplayName: String
}

/// Operator-facing runtime metadata used by the menu and startup diagnostics.
struct LlamaRuntimeDiagnostics: Equatable, Sendable {
    var runtimeDirectoryPath: String?
    var modelFilePath: String?
    var backendName: String?
    var contextWindowTokens: Int?
    var batchSize: Int?
    var threadCount: Int?
    var gpuLayerCount: Int?
    var lastLoadStatus: String?
    var lastError: String?
}

/// Runtime failures surfaced before or during in-process generation.
enum LlamaRuntimeError: LocalizedError {
    case unavailable(String)
    case cancelled
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .generationFailed(let message):
            return message
        case .cancelled:
            return "Runtime work was cancelled."
        }
    }
}

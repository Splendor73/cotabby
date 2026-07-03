import Foundation

/// File overview:
/// Pure state machine that gives a dismissed suggestion's regeneration a different sampler seed.
///
/// Why this file exists: the llama sampler runs with a fixed seed so identical contexts reproduce
/// identical ghost text (see `LlamaRuntimeCore.defaultSamplerSeed`). That determinism is right for
/// normal typing but wrong immediately after a dismissal: when the pipeline independently
/// regenerates for the same content, it reproduced the exact suggestion the user just rejected.
/// The tracker arms on dismissal and hands later generations for the *same* content signature a
/// deterministic seed walk (`baseSeed &+ retryCount`); the moment content changes it stands down,
/// so ordinary typing keeps full reproducibility. It never *triggers* a regeneration — it only
/// changes what a natural re-generation produces.
struct RetrySeedTracker: Equatable {
    /// The engine's fixed default, duplicated here because Support must not depend on the runtime
    /// actor; `RetrySeedTrackerTests` pins equality with `LlamaRuntimeCore.defaultSamplerSeed` so
    /// the two cannot drift apart silently.
    static let baseSeed: UInt32 = 0x00C0_FFEE

    private var armedSignature: String?
    private var retryCount: UInt32 = 0

    /// Arms (or advances) the retry walk for the dismissed content. A dismissal of different
    /// content restarts the walk at one.
    mutating func noteDismissal(contentSignature: String) {
        if armedSignature == contentSignature {
            retryCount &+= 1
        } else {
            armedSignature = contentSignature
            retryCount = 1
        }
    }

    /// The seed a generation for `contentSignature` should run with, or nil for the engine
    /// default. Querying with any other signature stands the tracker down permanently — new
    /// content means the user moved on, and returning to old content later is not a retry.
    mutating func seedOverride(for contentSignature: String) -> UInt32? {
        guard let armedSignature else {
            return nil
        }
        guard armedSignature == contentSignature else {
            standDown()
            return nil
        }
        return Self.baseSeed &+ retryCount
    }

    private mutating func standDown() {
        armedSignature = nil
        retryCount = 0
    }
}

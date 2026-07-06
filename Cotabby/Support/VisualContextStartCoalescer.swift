import Foundation

/// A focused field's identity for visual-context coalescing: the owning process, the AX element,
/// and the monotonic focus-change counter the tracker assigns.
nonisolated struct VisualContextFieldIdentity: Equatable {
    let processIdentifier: Int32
    let elementIdentifier: String
    let focusChangeSequence: UInt64

    /// Field identity for capture decisions: process + element, deliberately ignoring
    /// `focusChangeSequence`. Chromium/Electron flaps re-acquire the same element under a bumped
    /// sequence; treating that as a new field re-ran screenshot+OCR per flap and rewrote the
    /// stable prompt head each time, collapsing llama KV reuse to 8 of 289 decodes (measured
    /// 2026-07-05). The pid guards the CFHash-recycling risk the sequence used to cover: recycled
    /// element tokens never collide across live processes.
    func sameField(as other: VisualContextFieldIdentity) -> Bool {
        processIdentifier == other.processIdentifier
            && elementIdentifier == other.elementIdentifier
    }
}

/// What `VisualContextCoordinator.startSessionIfNeeded` should do for an incoming focus.
nonisolated enum VisualContextStartDecision: Equatable {
    /// Same field is already capturing or already waiting out its settle window — do nothing.
    case ignore
    /// The active session for this field was blocked on Screen Recording permission that is now
    /// granted — tear it down and start fresh.
    case recoverPermissionThenStart
    /// New or changed field — (re)arm the debounced capture.
    case start
}

/// Pure coalescing decision for the visual-context capture pipeline.
///
/// Chromium/Electron apps flap the focused AX element, calling `startSessionIfNeeded` repeatedly with
/// a churning `focusChangeSequence`. This collapses those repeats: a call matching the active or the
/// pending field is ignored, so the screenshot -> OCR -> summarize pipeline runs once focus is stable
/// instead of once per flap (the #280 retrigger storm). Kept pure so the invariants are unit-testable.
enum VisualContextStartCoalescer {
    static func decide(
        incoming: VisualContextFieldIdentity,
        active: VisualContextFieldIdentity?,
        activeIsBlockedOnScreenRecording: Bool,
        hasScreenRecordingPermission: Bool,
        pending: VisualContextFieldIdentity?
    ) -> VisualContextStartDecision {
        if let active, active.sameField(as: incoming) {
            if activeIsBlockedOnScreenRecording, hasScreenRecordingPermission {
                return .recoverPermissionThenStart
            }
            return .ignore
        }

        if let pending, pending.sameField(as: incoming) {
            return .ignore
        }

        return .start
    }
}

#!/bin/bash
# Runs the in-process suggestion eval (LlamaSuggestionEvalTests, 129 production-pipeline cases)
# against every requested GGUF and prints a comparison table. This is the "mimic a human typing
# across all models" harness: each case runs the real request factory -> prompt renderer (per the
# model's profile) -> llama engine -> normalizer -> display guards, and scores what would have
# been shown.
#
# Usage: model_matrix.sh [model1.gguf model2.gguf ...]
#        (no args: every .gguf in the app's runtime directory)
#
# The test host is Cotabby.app, so models resolve from
# ~/Library/Application Support/Cotabby/LlamaRuntime/ and the per-run model override rides the
# host's UserDefaults (xcodebuild does not forward environment variables into test hosts).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

RUNTIME_DIR="$HOME/Library/Application Support/Cotabby/LlamaRuntime"
HOST_BUNDLE_ID="com.jacobfu.tabby"
DEFAULTS_KEY="cotabbyEvalModelFilename"

if [ "$#" -gt 0 ]; then
  MODELS=("$@")
else
  MODELS=()
  while IFS= read -r -d '' f; do
    MODELS+=("$(basename "$f")")
  done < <(find "$RUNTIME_DIR" -maxdepth 1 -name "*.gguf" -print0 | sort -z)
fi

if [ "${#MODELS[@]}" -eq 0 ]; then
  echo "No .gguf models found in $RUNTIME_DIR" >&2
  exit 1
fi

echo "Matrix over ${#MODELS[@]} model(s): ${MODELS[*]}"

cleanup() { defaults delete "$HOST_BUNDLE_ID" "$DEFAULTS_KEY" 2>/dev/null || true; }
trap cleanup EXIT

for model in "${MODELS[@]}"; do
  if [ ! -f "$RUNTIME_DIR/$model" ]; then
    echo "--- SKIP $model (not present in $RUNTIME_DIR)" >&2
    continue
  fi
  echo "=== Evaluating $model ==="
  defaults write "$HOST_BUNDLE_ID" "$DEFAULTS_KEY" "$model"
  xcodebuild test -project Cotabby.xcodeproj -scheme Cotabby -destination 'platform=macOS' \
    -only-testing:CotabbyTests/LlamaSuggestionEvalTests \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) RUN_LLAMA_EVAL' \
    CODE_SIGNING_ALLOWED=NO -derivedDataPath build/DerivedData 2>&1 \
    | grep -E "Eval artifact written|MODEL |quality|precision|wrong|coverage|latency|TEST (SUCCEEDED|FAILED)|Skipped" || true
done

echo
echo "=== Comparison ==="
python3 - "$@" <<'PY'
import glob
import json

rows = []
for path in sorted(glob.glob("build/eval/llama-eval-*.json")):
    with open(path) as handle:
        report = json.load(handle)
    rows.append({
        "model": report.get("model", path),
        "quality": report.get("qualityScore"),
        "precision": report.get("precisionWhenShown"),
        "wrongShow": report.get("wrongShowRate"),
        "coverage": report.get("positiveCoverage"),
        "p50_ms": report.get("latencyP50Ms"),
        "p95_ms": report.get("latencyP95Ms"),
    })

if not rows:
    print("No artifacts found under build/eval/")
else:
    header = (
        f"{'model':44s} {'quality':>8s} {'precision':>10s} {'wrongShow':>10s} "
        f"{'coverage':>9s} {'p50 ms':>8s} {'p95 ms':>8s}"
    )
    print(header)
    print("-" * len(header))
    for row in rows:
        def fmt(value, places=3):
            return f"{value:.{places}f}" if isinstance(value, (int, float)) else "-"
        print(
            f"{row['model'][:44]:44s} {fmt(row['quality']):>8s} {fmt(row['precision']):>10s} "
            f"{fmt(row['wrongShow']):>10s} {fmt(row['coverage']):>9s} "
            f"{fmt(row['p50_ms'], 0):>8s} {fmt(row['p95_ms'], 0):>8s}"
        )
PY

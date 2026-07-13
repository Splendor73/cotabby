#!/bin/bash
# run_headtohead.sh — one app's external head-to-head capture. Starts the overlay watcher, runs
# the typing driver into the frontmost field, stops the watcher, and prints the metrics. Run once
# per app with the SAME corpus/WPM/target-field, then compare the two printouts.
#
# Usage: run_headtohead.sh <owner-name> <label> <wpm> <corpus> [outdir]
#   owner-name : window owner substring — "Cotypist" or "Cotabby Dev"
#   label      : output filename tag — e.g. cotypist / cotabby
# Example:
#   ./run_headtohead.sh "Cotabby Dev" cotabby 200 fixtures/headtohead-corpus.txt out/textedit
#   ./run_headtohead.sh "Cotypist"    cotypist 200 fixtures/headtohead-corpus.txt out/textedit
#
# Prereqs: Accessibility grant for THIS terminal (driver keystrokes), the target app running with
# the model/settings you want to compare, and the target text field focused when typing starts
# (the driver gives a 5s countdown). Clean-room: this observes public window metadata only.
set -euo pipefail

OWNER="${1:?usage: run_headtohead.sh <owner> <label> <wpm> <corpus> [outdir]}"
LABEL="${2:?usage: run_headtohead.sh <owner> <label> <wpm> <corpus> [outdir]}"
WPM="${3:?usage: run_headtohead.sh <owner> <label> <wpm> <corpus> [outdir]}"
CORPUS="${4:?usage: run_headtohead.sh <owner> <label> <wpm> <corpus> [outdir]}"
OUT="${5:-out}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$OUT"
KLOG="$OUT/keystrokes-$LABEL.jsonl"
OLOG="$OUT/overlay-$LABEL.jsonl"

echo "Watching overlay windows owned by \"$OWNER\" → $OLOG"
swift "$DIR/overlay_watcher.swift" --owner "$OWNER" --out "$OLOG" &
WATCHER=$!
trap 'kill "$WATCHER" 2>/dev/null || true' EXIT

"$DIR/typing_driver.sh" "$WPM" "$CORPUS" "$KLOG"
sleep 1
kill "$WATCHER" 2>/dev/null || true
wait "$WATCHER" 2>/dev/null || true

echo
python3 "$DIR/headtohead.py" --keystrokes "$KLOG" --overlay "$OLOG" --label "$LABEL"

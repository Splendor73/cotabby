#!/bin/bash
# typing_driver.sh — types a corpus into the frontmost app at a fixed WPM via System Events,
# logging each keystroke's SEND timestamp so an external watcher's overlay-appear timestamps can be
# joined into a keystroke→suggestion latency. Same driver on both Cotypist and Cotabby makes the
# comparison fair: any per-keystroke driver overhead is identical on both sides.
#
# Usage: typing_driver.sh <wpm> <text-file> <keystroke-log.jsonl>
# Requires: Accessibility permission for the invoking terminal (System Events synthetic keystrokes;
#           without it osascript fails with error 1002).
set -euo pipefail

WPM="${1:?usage: typing_driver.sh <wpm> <text-file> <keystroke-log.jsonl>}"
FILE="${2:?usage: typing_driver.sh <wpm> <text-file> <keystroke-log.jsonl>}"
LOG="${3:?usage: typing_driver.sh <wpm> <text-file> <keystroke-log.jsonl>}"

# 1 word = 5 chars (standard typing measure); delay per char in seconds.
DELAY=$(python3 -c "print(60.0 / ($WPM * 5))")

echo "Typing $(wc -c < "$FILE") chars at ${WPM} WPM (delay ${DELAY}s/char) → log $LOG."
echo "Focus the target field now; starting in 5 seconds..."
sleep 5

python3 - "$FILE" "$DELAY" "$LOG" <<'PY'
import json
import subprocess
import sys
import time

path, delay, logpath = sys.argv[1], float(sys.argv[2]), sys.argv[3]
text = open(path).read()
with open(logpath, "w") as log:
    for i, char in enumerate(text):
        if char == "\n":
            script = 'tell application "System Events" to key code 36'
            kind = "return"
        else:
            escaped = char.replace("\\", "\\\\").replace('"', '\\"')
            script = f'tell application "System Events" to keystroke "{escaped}"'
            kind = "char"
        # Timestamp on the same wall clock the overlay watcher uses (time.time() ==
        # Date().timeIntervalSince1970), recorded at the moment the key is issued.
        sent = time.time()
        subprocess.run(["osascript", "-e", script], check=True, capture_output=True)
        log.write(json.dumps({"t": sent, "i": i, "kind": kind}) + "\n")
        time.sleep(delay)
print("done")
PY

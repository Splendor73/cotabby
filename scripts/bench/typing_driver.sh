#!/bin/bash
# Types the contents of a text file into the frontmost app at a fixed WPM
# via System Events, so keystroke->suggestion benchmarks are reproducible
# across engine/model configurations.
# Usage: typing_driver.sh <wpm> <text-file>
# Requires: Accessibility permission for the invoking terminal app.
set -euo pipefail

WPM="${1:?usage: typing_driver.sh <wpm> <text-file>}"
FILE="${2:?usage: typing_driver.sh <wpm> <text-file>}"

# 1 word = 5 chars (standard typing measure); delay per char in seconds.
DELAY=$(python3 -c "print(60.0 / ($WPM * 5))")

echo "Typing $(wc -c < "$FILE") chars at ${WPM} WPM (delay ${DELAY}s/char)."
echo "Focus the target field now; starting in 5 seconds..."
sleep 5

python3 - "$FILE" "$DELAY" <<'PY'
import subprocess
import sys
import time

path, delay = sys.argv[1], float(sys.argv[2])
text = open(path).read()
for char in text:
    if char == "\n":
        script = 'tell application "System Events" to key code 36'
    else:
        escaped = char.replace("\\", "\\\\").replace('"', '\\"')
        script = f'tell application "System Events" to keystroke "{escaped}"'
    subprocess.run(["osascript", "-e", script], check=True, capture_output=True)
    time.sleep(delay)
print("done")
PY

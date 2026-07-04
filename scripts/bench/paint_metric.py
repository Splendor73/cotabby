#!/usr/bin/env python3
"""Felt-latency metric: keystroke -> first ghost paint, from cotabby.jsonl stage lines.

Usage: paint_metric.py <cotabby.jsonl> [--since 2026-07-04T12:00:00Z]

Pairs each "painted" stage line with the most recent preceding "keystroke" stage line and keeps
only the FIRST paint after each keystroke (streamed partials repaint; the first one is what the
user feels). A keystroke with no following paint before the next keystroke simply contributes no
sample — suppressions and cancelled generations are not latency.
"""
import json
import sys
from datetime import datetime, timezone


def parse_ts(value):
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    path = sys.argv[1]
    since = None
    if "--since" in sys.argv:
        since = parse_ts(sys.argv[sys.argv.index("--since") + 1])
        if since and since.tzinfo is None:
            since = since.replace(tzinfo=timezone.utc)

    samples_ms = []
    last_keystroke = None
    keystrokes = 0
    with open(path) as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            stage = record.get("stage")
            if stage not in ("keystroke", "painted"):
                continue
            ts = parse_ts(record.get("timestamp"))
            if ts is None or (since and ts < since):
                continue
            if stage == "keystroke":
                last_keystroke = ts
                keystrokes += 1
            elif stage == "painted" and last_keystroke is not None:
                samples_ms.append((ts - last_keystroke).total_seconds() * 1000.0)
                # Only the first paint after a keystroke counts; later repaints (streamed
                # partials, geometry re-anchors) are not felt latency.
                last_keystroke = None

    samples_ms.sort()

    def pct(fraction):
        if not samples_ms:
            return None
        index = min(len(samples_ms) - 1, max(0, round(fraction * (len(samples_ms) - 1))))
        return samples_ms[index]

    if not samples_ms:
        print(f"keystrokes: {keystrokes}   paints: 0 — no samples")
        return
    print(
        f"keystrokes: {keystrokes}   first-paints: {len(samples_ms)}   "
        f"paint p50={pct(0.50):.0f}ms  p95={pct(0.95):.0f}ms  max={samples_ms[-1]:.0f}ms"
    )


if __name__ == "__main__":
    main()

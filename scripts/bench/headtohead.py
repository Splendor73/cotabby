#!/usr/bin/env python3
"""headtohead.py — join a typing-driver keystroke log with an overlay-watcher log and score one
app's autocomplete behavior on three externally-observable dimensions. Run once per app (Cotypist,
Cotabby) on the same corpus/WPM/field, then compare the two reports side by side.

Inputs (both JSONL, same wall clock):
  keystrokes: {"t": <epoch s>, "i": <index>, "kind": "char"|"return"}      (from typing_driver.sh)
  overlay:    {"t": <epoch s>, "visible": true, "x","y","w","h"} | {"t","visible": false}
              (transition log from overlay_watcher.swift)

Metrics (all from observed window behavior — no app internals, works on a closed binary):
  latency     — per keystroke, time to the next overlay appear/move within a window; p50/p95/max.
  persistence — fraction of keystrokes that had an overlay visible within `within` seconds
                (the "keeps a suggestion up while I type fast" property).
  placement   — with --line-top/--line-bottom given (the typed line's screen band), the fraction of
                visible-overlay samples whose vertical span intersects that band = overlap rate.

Usage:
  headtohead.py --keystrokes k.jsonl --overlay o.jsonl [--within 0.6]
                [--line-top Y --line-bottom Y] [--label Cotypist]
  headtohead.py --selftest
"""
import argparse
import bisect
import json
import sys


def _load(path):
    rows = []
    with open(path) as handle:
        for line in handle:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def _percentile(sorted_vals, pct):
    if not sorted_vals:
        return None
    idx = min(len(sorted_vals) - 1, int(len(sorted_vals) * pct))
    return sorted_vals[idx]


def analyze(keystrokes, overlay, within=0.6):
    """Pure scoring. keystrokes/overlay are lists of dicts; returns a metrics dict.

    An overlay "appear/move" is any transition whose `visible` is true. Latency for a keystroke is
    the wait until the first such appear-event strictly after it and within `within` seconds;
    keystrokes with no appear in that window are misses (counted for persistence, excluded from the
    latency percentiles, which describe only shown suggestions).
    """
    appears = sorted(e["t"] for e in overlay if e.get("visible"))
    latencies = []
    shown = 0
    for key in keystrokes:
        t = key["t"]
        pos = bisect.bisect_right(appears, t)
        if pos < len(appears) and appears[pos] - t <= within:
            latencies.append((appears[pos] - t) * 1000.0)
            shown += 1
    latencies.sort()
    total = len(keystrokes)
    return {
        "keystrokes": total,
        "shown_within_window": shown,
        "persistence": (shown / total) if total else 0.0,
        "latency_ms_p50": _percentile(latencies, 0.50),
        "latency_ms_p95": _percentile(latencies, 0.95),
        "latency_ms_max": latencies[-1] if latencies else None,
    }


def overlap_rate(overlay, line_top, line_bottom):
    """Fraction of visible samples whose vertical span [y, y+h] intersects the typed line band.
    A high rate means the overlay sits on top of the text line (bad). Needs the caller to pass the
    line band; returns None when not provided."""
    if line_top is None or line_bottom is None:
        return None
    visibles = [e for e in overlay if e.get("visible")]
    if not visibles:
        return None
    hits = 0
    for e in visibles:
        top, bottom = e["y"], e["y"] + e["h"]
        if top < line_bottom and bottom > line_top:
            hits += 1
    return hits / len(visibles)


def _selftest():
    # Keystrokes at t=0,1,2,3. Overlay appears 0.1s after k0 (shown), 0.05s after k1 (shown),
    # never for k2, and 0.9s after k3 (miss: beyond within=0.6). p50 of {100ms,50ms} = 100ms.
    keystrokes = [{"t": 0.0}, {"t": 1.0}, {"t": 2.0}, {"t": 3.0}]
    overlay = [
        {"t": 0.10, "visible": True, "x": 0, "y": 100, "w": 200, "h": 30},
        {"t": 0.40, "visible": False},
        {"t": 1.05, "visible": True, "x": 0, "y": 500, "w": 200, "h": 30},
        {"t": 1.30, "visible": False},
        {"t": 3.90, "visible": True, "x": 0, "y": 100, "w": 200, "h": 30},
    ]
    m = analyze(keystrokes, overlay, within=0.6)
    assert m["keystrokes"] == 4, m
    assert m["shown_within_window"] == 2, m
    assert abs(m["persistence"] - 0.5) < 1e-9, m
    assert abs(m["latency_ms_p50"] - 100.0) < 1e-6, m
    assert abs(m["latency_ms_max"] - 100.0) < 1e-6, m
    # Placement: one visible sample at y=100..130 overlaps band 110..120; the y=500 one does not;
    # the y=100 reappear overlaps → 2 of 3 visible samples hit the line band.
    rate = overlap_rate(overlay, line_top=110, line_bottom=120)
    assert abs(rate - (2 / 3)) < 1e-9, rate
    # No band → None.
    assert overlap_rate(overlay, None, None) is None
    # Empty input is safe.
    empty = analyze([], [], within=0.6)
    assert empty["persistence"] == 0.0 and empty["latency_ms_p50"] is None, empty
    print("selftest OK")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--keystrokes")
    parser.add_argument("--overlay")
    parser.add_argument("--within", type=float, default=0.6)
    parser.add_argument("--line-top", type=float)
    parser.add_argument("--line-bottom", type=float)
    parser.add_argument("--label", default="app")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()

    if args.selftest:
        _selftest()
        return

    if not args.keystrokes or not args.overlay:
        parser.error("--keystrokes and --overlay are required (or use --selftest)")

    keystrokes = _load(args.keystrokes)
    overlay = _load(args.overlay)
    metrics = analyze(keystrokes, overlay, within=args.within)
    rate = overlap_rate(overlay, args.line_top, args.line_bottom)

    print(f"=== {args.label} ===")
    print(f"keystrokes            {metrics['keystrokes']}")
    print(f"persistence           {metrics['persistence'] * 100:.0f}/100 keystrokes had a suggestion up")
    lat50 = metrics["latency_ms_p50"]
    lat95 = metrics["latency_ms_p95"]
    latmax = metrics["latency_ms_max"]
    print(f"latency p50/p95/max   "
          f"{'n/a' if lat50 is None else f'{lat50:.0f}'}/"
          f"{'n/a' if lat95 is None else f'{lat95:.0f}'}/"
          f"{'n/a' if latmax is None else f'{latmax:.0f}'} ms")
    if rate is not None:
        print(f"overlap rate          {rate * 100:.0f}% of visible samples cover the typed line")


if __name__ == "__main__":
    main()

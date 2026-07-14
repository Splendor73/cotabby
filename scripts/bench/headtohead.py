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


def _visible_at(transitions, t):
    """Overlay visibility state at time t, reconstructed from the transition log (state is
    piecewise-constant between transitions; hidden before the first one)."""
    times = [e["t"] for e in transitions]
    pos = bisect.bisect_right(times, t) - 1
    return pos >= 0 and bool(transitions[pos].get("visible"))


def analyze(keystrokes, overlay, within=0.6):
    """Pure scoring. keystrokes/overlay are transition lists; returns a metrics dict.

    Two distinct things, measured from the reconstructed visibility STATE (not raw transitions,
    which under-count a still card and mis-pair a moving one — the flaw cross-validation exposed):

    * persistence — fraction of keystrokes with the overlay visible at any instant in
      [t, t+within]. This is the "keeps a suggestion up while I type" property.
    * appear latency — for keystrokes where the overlay was HIDDEN at the keystroke, the wait until
      it next becomes visible within `within`. This is how fast a fresh suggestion shows; it does
      not count keystrokes where a suggestion was already up (those are instant by definition).
    """
    transitions = sorted(overlay, key=lambda e: e["t"])
    appears = [e["t"] for e in transitions if e.get("visible")]
    appears.sort()
    latencies = []
    shown = 0
    for key in keystrokes:
        t = key["t"]
        # Visible at any instant in [t, t+within]?
        visible_here = _visible_at(transitions, t)
        pos = bisect.bisect_right(appears, t)
        next_appear = appears[pos] if pos < len(appears) else None
        appears_soon = next_appear is not None and next_appear - t <= within
        if visible_here or appears_soon:
            shown += 1
        # Cold appear-latency: only when hidden at the keystroke and a fresh appearance follows.
        if not visible_here and appears_soon:
            latencies.append((next_appear - t) * 1000.0)
    latencies.sort()
    total = len(keystrokes)
    # Time-to-first-suggestion: from the first keystroke to the first overlay appearance. The
    # cleanest cross-app latency number — how long a cold field waits for its first suggestion.
    first_suggestion_ms = None
    if keystrokes and appears:
        first_key = min(k["t"] for k in keystrokes)
        after = [a for a in appears if a >= first_key]
        if after:
            first_suggestion_ms = (after[0] - first_key) * 1000.0
    return {
        "keystrokes": total,
        "shown_within_window": shown,
        "persistence": (shown / total) if total else 0.0,
        "cold_appears": len(latencies),
        "first_suggestion_ms": first_suggestion_ms,
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
    # k0=0.0 hidden→appears 0.10 (shown, cold 100ms); k1=0.2 during the 0.10–0.40 visible span
    # (shown, NO cold latency — already up); k2=1.0 hidden→appears 1.05 (shown, cold 50ms);
    # k3=2.0 and k4=3.0 hidden with next appear 3.90 beyond within (misses). shown=3/5.
    keystrokes = [{"t": 0.0}, {"t": 0.2}, {"t": 1.0}, {"t": 2.0}, {"t": 3.0}]
    overlay = [
        {"t": 0.10, "visible": True, "x": 0, "y": 100, "w": 200, "h": 30},
        {"t": 0.40, "visible": False},
        {"t": 1.05, "visible": True, "x": 0, "y": 500, "w": 200, "h": 30},
        {"t": 1.30, "visible": False},
        {"t": 3.90, "visible": True, "x": 0, "y": 100, "w": 200, "h": 30},
    ]
    m = analyze(keystrokes, overlay, within=0.6)
    assert m["keystrokes"] == 5, m
    assert m["shown_within_window"] == 3, m
    assert abs(m["persistence"] - 0.6) < 1e-9, m
    assert m["cold_appears"] == 2, m
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

    # Skip keystrokes the driver failed to send (ok:false) — they never reached the app.
    keystrokes = [k for k in _load(args.keystrokes) if k.get("ok", True)]
    overlay = _load(args.overlay)
    metrics = analyze(keystrokes, overlay, within=args.within)
    rate = overlap_rate(overlay, args.line_top, args.line_bottom)

    print(f"=== {args.label} ===")
    print(f"keystrokes            {metrics['keystrokes']}")
    fst = metrics["first_suggestion_ms"]
    print(f"time to 1st suggestion {'n/a' if fst is None else f'{fst:.0f} ms'}")
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

#!/usr/bin/env python3
"""Summarize Cotabby llm-io.jsonl generation latencies (p50/p95/max, per engine).

Usage: analyze_logs.py <llm-io.jsonl> [--since 2026-07-01T12:00:00Z]

Field names are read defensively: latency may appear as latency_ms (number)
or latency (seconds float) depending on log site. Records without a usable
latency are counted as skipped rather than failing the run, so a mixed log
stream (state transitions interleaved with generations) analyzes cleanly.
"""
import json
import sys
from datetime import datetime, timezone


def parse_ts(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def latency_ms(record):
    if isinstance(record.get("latency_ms"), (int, float)):
        return float(record["latency_ms"])
    if isinstance(record.get("latency"), (int, float)):
        return float(record["latency"]) * 1000.0
    return None


def percentile(sorted_values, fraction):
    if not sorted_values:
        return None
    index = min(len(sorted_values) - 1, max(0, round(fraction * (len(sorted_values) - 1))))
    return sorted_values[index]


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    path = sys.argv[1]
    since = None
    if "--since" in sys.argv:
        since = parse_ts(sys.argv[sys.argv.index("--since") + 1])
        if since and since.tzinfo is None:
            since = since.replace(tzinfo=timezone.utc)

    by_engine = {}
    skipped = 0
    with open(path) as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                skipped += 1
                continue
            if since:
                ts = parse_ts(record.get("timestamp"))
                if ts and ts < since:
                    continue
            value = latency_ms(record)
            if value is None:
                skipped += 1
                continue
            by_engine.setdefault(record.get("engine", "unknown"), []).append(value)

    total = sum(len(v) for v in by_engine.values())
    print(f"records: {total}   skipped: {skipped}")
    for engine, values in sorted(by_engine.items()):
        values.sort()
        print(
            f"  {engine:12s} n={len(values):4d}  "
            f"p50={percentile(values, 0.50):7.1f}ms  "
            f"p95={percentile(values, 0.95):7.1f}ms  "
            f"max={values[-1]:7.1f}ms"
        )


if __name__ == "__main__":
    main()

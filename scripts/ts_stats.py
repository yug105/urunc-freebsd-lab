#!/usr/bin/env python3
"""Summarise urunc timestamp logs (zerolog JSON, "time" in nanoseconds).

Usage: ts_stats.py <label>=<zlog> [<label>=<zlog> ...]

For every container in a log it computes:
  create: TS02 - TS01  (InitialSetup, where rootfs selection runs)
  start:  TS18 - TS11  (urunc start invoked -> monitor execve)
and prints min / median / p95 / max in microseconds as a Markdown table.
"""
import json
import statistics
import sys
from collections import defaultdict

SPANS = {
    "create (TS01->TS02)": ("TS01", "TS02"),
    "start (TS11->TS18)": ("TS11", "TS18"),
}


def load(path):
    per = defaultdict(dict)
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            cid = rec.get("containerID")
            tsid = rec.get("timestampID")
            if cid and tsid and "time" in rec:
                per[cid][tsid] = int(rec["time"])
    return per


def pct(values, p):
    values = sorted(values)
    k = max(0, min(len(values) - 1, round(p / 100 * (len(values) - 1))))
    return values[k]


def main(args):
    print("| run | span | n | min µs | median µs | p95 µs | max µs |")
    print("|---|---|---|---|---|---|---|")
    for arg in args:
        label, path = arg.split("=", 1)
        per = load(path)
        for span, (a, b) in SPANS.items():
            vals = [(ts[b] - ts[a]) / 1000 for ts in per.values() if a in ts and b in ts]
            if not vals:
                print(f"| {label} | {span} | 0 | - | - | - | - |")
                continue
            print(f"| {label} | {span} | {len(vals)} | {min(vals):.0f} | "
                  f"{statistics.median(vals):.0f} | {pct(vals, 95):.0f} | {max(vals):.0f} |")


if __name__ == "__main__":
    main(sys.argv[1:])

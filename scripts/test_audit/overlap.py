#!/usr/bin/env python3
"""Coverage-overlap analysis over run_coverage.py output.

  python3 scripts/test_audit/overlap.py --pkg server [--min-lines 5]

Writes build/test_audit/overlap_<pkg>.md and overlap_<pkg>.csv:
  * unique_lines   lines of lib/ covered by this test file and no other
  * marginal       greedy set-cover marginal gain (files sorted by gain/cost)
  * subset_of      other files whose coverage fully contains this one's
  * best_jaccard   most-similar other file (same-SUT neighbours are the merge candidates)
  * sec            summed test time (runtime JSON reporter)
Verdict heuristics (candidates only — a human must read the tests):
  ZERO_UNIQUE   covers nothing no other file covers  -> delete/merge candidate
  SUBSET        coverage is a subset of one other file -> merge into it
  TWIN          Jaccard >= 0.9 with another file       -> merge
  KEEP          has unique lines
Line coverage proves *execution*, not *assertion*: ZERO_UNIQUE tests can still pin
distinct behaviour (different branch outcomes, error messages). Review the test names.
"""
import argparse, csv, json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pkg", required=True)
    ap.add_argument("--common-cut", type=float, default=0.15,
                    help="lines hit by more than this fraction of files are infrastructure (module load, DI) and ignored for similarity")
    ap.add_argument("--min-lines", type=int, default=1, help="ignore files covering fewer lines (smoke/arch tests)")
    a = ap.parse_args()
    d = ROOT / "build/test_audit/cov" / a.pkg
    recs = [json.loads(p.read_text()) for p in sorted(d.glob("*.json"))]
    bad = [r["file"] for r in recs if not r["ok"]]
    cov, cost, ntests = {}, {}, {}
    for r in recs:
        s = {f"{f}:{l}" for f, ls in r["covered"].items() for l in ls}
        cov[r["file"]] = s
        cost[r["file"]] = max(sum(t["ms"] for t in r["tests"]) / 1000.0, 0.01)
        ntests[r["file"]] = len(r["tests"])
    files = [f for f in cov if len(cov[f]) >= a.min_lines]
    owners = defaultdict(set)
    for f in files:
        for ln in cov[f]: owners[ln].add(f)
    cut = max(3, int(a.common_cut * len(files)))
    info = {f: {ln for ln in cov[f] if len(owners[ln]) <= cut} for f in files}
    uniq = {f: sum(1 for ln in cov[f] if len(owners[ln]) == 1) for f in files}
    # greedy cover
    remaining = set(owners); order = []; marginal = {}
    left = set(files)
    while remaining and left:
        best = max(left, key=lambda f: (len(cov[f] & remaining) / cost[f], len(cov[f] & remaining)))
        g = len(cov[best] & remaining)
        if g == 0: break
        marginal[best] = g; order.append(best); remaining -= cov[best]; left.discard(best)
    # pairwise (inverted index to avoid n^2 on disjoint files)
    best_j, subset_of = {}, defaultdict(list)
    for f in files:
        cnt = defaultdict(int)
        for ln in info[f]:
            for o in owners[ln]:
                if o != f: cnt[o] += 1
        bj = (0.0, "")
        for o, inter in cnt.items():
            j = inter / (len(info[f]) + len(info[o]) - inter)
            if j > bj[0]: bj = (j, o)
            if inter == len(info[f]) and len(info[o]) >= len(info[f]): subset_of[f].append(o)
        best_j[f] = bj
    rows = []
    for f in files:
        if uniq[f] == 0 and subset_of[f]: v = "SUBSET"
        elif uniq[f] == 0: v = "ZERO_UNIQUE"
        elif best_j[f][0] >= 0.9: v = "TWIN"
        else: v = "KEEP"
        rows.append(dict(file=f, verdict=v, tests=ntests[f], sec=round(cost[f], 2), lines=len(info[f]),
                         unique_lines=uniq[f], marginal=marginal.get(f, 0),
                         best_jaccard=round(best_j[f][0], 2), best_other=best_j[f][1],
                         subset_of=";".join(subset_of[f][:3])))
    rows.sort(key=lambda r: (r["verdict"] == "KEEP", -r["tests"]))
    out = ROOT / "build/test_audit"
    with open(out / f"overlap_{a.pkg}.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
    tot_t = sum(ntests.values()); tot_s = sum(cost.values())
    cand = [r for r in rows if r["verdict"] != "KEEP"]
    md = [f"# Overlap — {a.pkg}", "",
          f"- files analysed: {len(files)} (failed/ignored: {len(bad)}), tests: {tot_t}, summed test time: {tot_s:.0f}s",
          f"- lib lines covered by ≥1 test: {len(owners)}",
          f"- greedy minimal cover needs **{len(order)}** of {len(files)} files ({sum(ntests[f] for f in order)} of {tot_t} tests)",
          f"- non-KEEP files: {len(cand)} covering {sum(r['tests'] for r in cand)} tests / {sum(r['sec'] for r in cand):.0f}s",
          "", "| verdict | file | tests | sec | lines | unique | best Jaccard | other |", "|---|---|---|---|---|---|---|---|"]
    for r in cand[:300]:
        md.append(f"| {r['verdict']} | {r['file']} | {r['tests']} | {r['sec']} | {r['lines']} | {r['unique_lines']} | {r['best_jaccard']} | {r['best_other'] or r['subset_of']} |")
    if bad: md += ["", "## Failed runs (excluded)"] + [f"- {b}" for b in bad]
    slow = sorted(((t["ms"], r["file"], t["name"]) for r in recs for t in r["tests"]), reverse=True)[:25]
    md += ["", "## 25 slowest tests"] + [f"- {ms} ms — {f} — {n}" for ms, f, n in slow]
    (out / f"overlap_{a.pkg}.md").write_text("\n".join(md) + "\n")
    print("\n".join(md[:12]))


if __name__ == "__main__":
    main()

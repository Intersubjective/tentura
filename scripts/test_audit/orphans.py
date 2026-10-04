#!/usr/bin/env python3
"""Find lib files nothing (except generated code / tests) imports, and the tests that exist only for them.

  python3 scripts/test_audit/orphans.py

Orphan lib file = no non-generated lib file imports it (entry points main.dart and
bin/*.dart excluded).  A test file whose *only* project imports are orphans (plus
support/fixtures) is testing dead code -> deletion candidate together with the code.
Output: build/test_audit/orphans.csv  (orphan_lib, tests_importing_it)
Caveat: conditional imports, part files, reflection and DI-by-name hide edges; treat as a lead.
"""
import csv, re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PKGS = {"package:tentura/": ROOT / "packages/client/lib", "package:tentura_server/": ROOT / "packages/server/lib",
        "package:tentura_root/": ROOT / "lib", "package:force_directed_graphview/": ROOT / "packages/force_directed_graphview/lib"}
GEN = re.compile(r"\.(g|gr|gql|freezed|config|schema|data|var|req|mocks)\.dart$|/_g/")
IMP = re.compile(r"""^\s*(?:import|export|part)\s+['"]([^'"]+)['"]|\bif\s*\([^)]*\)\s*['"]([^'"]+)['"]""", re.M)
DI = re.compile(r"@(?:[Ll]azy)?[Ss]ingleton|@[Ii]njectable|@module|@RoutePage|@Environment|@Named|@factoryMethod")


def flat(ms):
    return [a or b for a, b in ms]


def resolve(frm, imp):
    for pre, base in PKGS.items():
        if imp.startswith(pre): return base / imp[len(pre):]
    if imp.startswith(("dart:", "package:")): return None
    return (frm.parent / imp).resolve()


def main():
    libs = [p for base in PKGS.values() for p in base.rglob("*.dart")]
    libset = set(libs)
    importers = defaultdict(set)
    for f in libs:
        if GEN.search(str(f)): continue
        for i in flat(IMP.findall(f.read_text(errors="replace"))):
            t = resolve(f, i)
            if t in libset: importers[t].add(f)
    entry = lambda p: p.name == "main.dart" or "/bin/" in str(p)
    orphans = {f for f in libs if not GEN.search(str(f)) and not entry(f) and not importers[f]
               and not DI.search(f.read_text(errors="replace"))}
    tests = list(ROOT.glob("packages/*/test/**/*_test.dart")) + list(ROOT.glob("test/**/*_test.dart"))
    hits = defaultdict(list)
    for t in tests:
        for i in flat(IMP.findall(t.read_text(errors="replace"))):
            r = resolve(t, i)
            if r in orphans: hits[r].append(str(t.relative_to(ROOT)))
    out = ROOT / "build/test_audit/orphans.csv"
    with open(out, "w", newline="") as fh:
        w = csv.writer(fh); w.writerow(["orphan_lib", "tests_importing"])
        for o in sorted(orphans): w.writerow([str(o.relative_to(ROOT)), ";".join(hits.get(o, []))])
    print(f"{len(orphans)} orphan lib files; {sum(1 for o in orphans if hits.get(o))} have tests -> {out}")


if __name__ == "__main__":
    main()

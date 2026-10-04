#!/usr/bin/env python3
"""Static inventory + redundancy heuristics for Dart/Flutter tests.

Usage: python3 scripts/test_audit/inventory.py [--out DIR]

Produces (default DIR=build/test_audit):
  tests.jsonl          one record per test()/testWidgets()/blocTest()/... call
  files.csv            one row per *_test.dart file (size, #tests, SUT, skips)
  dup_bodies.csv       tests whose normalized bodies are identical / near-identical
  stale_files.csv      test files importing project paths that no longer exist
  skipped.csv          tests/groups carrying skip:
  report.md            human-readable summary

Parsing is regex + brace matching: good enough for ranking, not for proof.
Loop-generated tests (`for (...) test(...)`) count once here; the runtime
JSON report (run_coverage.sh --json) has the true count.
"""
import argparse, csv, hashlib, json, os, re, sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PKGS = ["client", "server", "force_directed_graphview", "ferry_generator",
        "image_cropper_for_web", "tentura_lints"]
CALL = re.compile(r"\b(test|testWidgets|blocTest|group|setUp|tearDown|setUpAll|tearDownAll)"
                  r"\s*(?:<[^>(]*>)?\s*\(")
STR = re.compile(r"""\s*(r?)(?:'((?:\\.|[^'\\])*)'|"((?:\\.|[^"\\])*)")""", re.S)
GENERATED = re.compile(r"(\.(g|gr|gql|freezed|config|schema|data|var|req)\.dart|/_g/|/l10n/|\.mocks\.dart)$")
IMPORT = re.compile(r"""import\s+['"]([^'"]+)['"]""")


def match_paren(s, i):
    """i at '(' -> index after matching ')', skipping strings/comments."""
    d, n = 0, len(s)
    while i < n:
        c = s[i]
        if c in "'\"":
            q = c
            triple = s[i:i + 3] == q * 3
            if triple:
                j = s.find(q * 3, i + 3)
                i = n if j < 0 else j + 3
                continue
            i += 1
            while i < n and s[i] != q:
                i += 2 if s[i] == "\\" else 1
        elif c == "/" and s[i:i + 2] == "//":
            j = s.find("\n", i); i = n if j < 0 else j
        elif c == "/" and s[i:i + 2] == "/*":
            j = s.find("*/", i); i = n if j < 0 else j + 2
            continue
        elif c in "([{":
            d += 1
        elif c in ")]}":
            d -= 1
            if d == 0:
                return i + 1
        i += 1
    return n


def parse_file(path, text):
    """Return list of dict(kind,name,start,end,body,depth_path,skip,tags)."""
    out, stack = [], []  # stack of (end_idx, group_name)
    for m in CALL.finditer(text):
        kind = m.group(1)
        if kind in ("setUp", "tearDown", "setUpAll", "tearDownAll"):
            continue
        # skip matches inside strings is rare for these tokens; ignore.
        open_i = m.end() - 1
        end = match_paren(text, open_i)
        sm = STR.match(text, open_i + 1)
        name = (sm.group(2) or sm.group(3)) if sm else "<dynamic>"
        while stack and stack[-1][0] <= m.start():
            stack.pop()
        args = text[open_i:end]
        rec = dict(kind=kind, name=name, start=text.count("\n", 0, m.start()) + 1,
                   end=text.count("\n", 0, end) + 1, body=args,
                   group="/".join(g for _, g in stack),
                   skip=bool(re.search(r"\bskip\s*:\s*(?:true\b|['\"])", args[:400] + args[-300:])),
                   tags=re.findall(r"tags\s*:\s*(?:\[([^\]]*)\]|'([^']*)')", args[-300:]))
        if kind == "group":
            stack.append((end, name))
        out.append(rec)
    return out


def normalize(body):
    b = re.sub(r"//[^\n]*", "", body)
    b = re.sub(r"'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"", "S", b)
    b = re.sub(r"\b\d+(?:\.\d+)?\b", "N", b)
    b = re.sub(r"\s+", " ", b)
    return b


def shingles(norm, k=5):
    toks = re.findall(r"\w+|[^\w\s]", norm)
    return {" ".join(toks[i:i + k]) for i in range(max(1, len(toks) - k + 1))}


def resolve_import(pkg_dir, test_file, imp):
    """Return Path if project-local import, else None (external)."""
    if imp.startswith("package:tentura/"):
        return ROOT / "packages/client/lib" / imp[len("package:tentura/"):]
    if imp.startswith("package:tentura_server/"):
        return ROOT / "packages/server/lib" / imp[len("package:tentura_server/"):]
    if imp.startswith("package:tentura_root/"):
        return ROOT / "lib" / imp[len("package:tentura_root/"):]
    if imp.startswith(("dart:", "package:")):
        return None
    return (test_file.parent / imp).resolve()


def sut_for(test_path, pkg_dir):
    rel = test_path.relative_to(pkg_dir / "test")
    name = re.sub(r"_(pg_)?test\.dart$", ".dart", rel.name)
    for cand in (pkg_dir / "lib" / rel.parent / name,):
        if cand.exists():
            return str(cand.relative_to(ROOT))
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "build/test_audit"))
    a = ap.parse_args()
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    tests, files, stale, skipped = [], [], [], []
    test_roots = [(ROOT / "packages" / p) for p in PKGS] + [ROOT]
    seen = set()
    for pkg_dir in test_roots:
        tdir = pkg_dir / "test"
        if not tdir.is_dir():
            continue
        for f in sorted(tdir.rglob("*_test.dart")):
            if f in seen: continue
            seen.add(f)
            text = f.read_text(errors="replace")
            recs = parse_file(f, text)
            pkg = pkg_dir.name if pkg_dir != ROOT else "root"
            rel = str(f.relative_to(ROOT))
            leaf = [r for r in recs if r["kind"] != "group"]
            for r in leaf:
                norm = normalize(r["body"])
                r.update(pkg=pkg, file=rel, norm=norm,
                         hash=hashlib.sha1(norm.encode()).hexdigest()[:12],
                         loc=r["end"] - r["start"] + 1)
                tests.append(r)
            for r in recs:
                if r["skip"]:
                    skipped.append((rel, r["kind"], r["group"], r["name"], r["start"]))
            missing = []
            for imp in IMPORT.findall(text):
                p = resolve_import(pkg_dir, f, imp)
                if p is not None and not p.exists() and not GENERATED.search(imp):
                    missing.append(imp)
            if missing:
                stale.append((rel, ";".join(missing)))
            files.append(dict(pkg=pkg, file=rel, lines=text.count("\n") + 1,
                              tests=len(leaf), skipped=sum(r["skip"] for r in recs),
                              pg="pg" in rel or "'pg'" in text,
                              loops=len(re.findall(r"\bfor\s*\(.*\bin\b.*\)\s*\{?\s*\n?\s*(?:test|testWidgets|blocTest)\b", text)),
                              sut=sut_for(f, pkg_dir)))
    with open(out / "tests.jsonl", "w") as fh:
        for t in tests:
            d = {k: t[k] for k in ("pkg", "file", "group", "name", "kind", "start", "end", "loc", "hash", "skip")}
            fh.write(json.dumps(d, ensure_ascii=False) + "\n")
    with open(out / "files.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(files[0].keys())); w.writeheader(); w.writerows(files)
    with open(out / "stale_files.csv", "w", newline="") as fh:
        csv.writer(fh).writerows([("file", "missing_imports")] + stale)
    with open(out / "skipped.csv", "w", newline="") as fh:
        csv.writer(fh).writerows([("file", "kind", "group", "name", "line")] + skipped)

    # --- duplicate / near-duplicate bodies -----------------------------------
    by_hash = defaultdict(list)
    for t in tests:
        if t["loc"] >= 4:
            by_hash[t["hash"]].append(t)
    dups = [g for g in by_hash.values() if len(g) > 1]
    # near duplicates: within same package, compare shingle Jaccard using LSH-ish buckets
    cand = [t for t in tests if t["loc"] >= 8 and t["hash"] not in {g[0]["hash"] for g in dups}]
    for t in cand:
        t["sh"] = shingles(t["norm"])
    buckets = defaultdict(list)
    for t in cand:
        for s in sorted(t["sh"])[:4]:  # min-ish hash sampling
            buckets[(t["pkg"], hashlib.md5(s.encode()).hexdigest()[:6])].append(t)
    pairs = {}
    for b in buckets.values():
        if len(b) > 60: continue
        for i in range(len(b)):
            for j in range(i + 1, len(b)):
                x, y = b[i], b[j]
                if x is y or (x["file"], x["start"]) >= (y["file"], y["start"]): continue
                k = (x["file"], x["start"], y["file"], y["start"])
                if k in pairs: continue
                inter = len(x["sh"] & y["sh"]); uni = len(x["sh"] | y["sh"])
                if uni and inter / uni >= 0.85:
                    pairs[k] = (round(inter / uni, 2), x, y)
    with open(out / "dup_bodies.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["similarity", "a_file", "a_line", "a_name", "b_file", "b_line", "b_name"])
        for g in dups:
            for y in g[1:]:
                x = g[0]
                w.writerow([1.0, x["file"], x["start"], x["name"], y["file"], y["start"], y["name"]])
        for sim, x, y in sorted(pairs.values(), key=lambda p: -p[0]):
            w.writerow([sim, x["file"], x["start"], x["name"], y["file"], y["start"], y["name"]])

    # --- report ----------------------------------------------------------------
    per_pkg = defaultdict(lambda: [0, 0, 0])
    for f in files:
        p = per_pkg[f["pkg"]]; p[0] += 1; p[1] += f["tests"]; p[2] += f["lines"]
    top = sorted(files, key=lambda f: -f["tests"])[:15]
    names = defaultdict(list)
    for t in tests: names[(t["pkg"], t["name"])].append(t["file"])
    same_name = sorted(((k, v) for k, v in names.items() if len(v) > 2 and k[1] != "<dynamic>"),
                       key=lambda kv: -len(kv[1]))[:15]
    lines = ["# Test audit — static report", "", "| pkg | files | tests | lines |", "|---|---|---|---|"]
    for k, v in sorted(per_pkg.items()): lines.append(f"| {k} | {v[0]} | {v[1]} | {v[2]} |")
    lines += ["", f"- exact-duplicate body groups: {len(dups)} (tests involved: {sum(len(g) for g in dups)})",
              f"- near-duplicate pairs (Jaccard>=0.85): {len(pairs)}",
              f"- skipped tests/groups: {len(skipped)}",
              f"- test files importing missing project paths: {len(stale)}",
              "", "## Largest files by test count"]
    lines += [f"- {f['tests']:4d}  {f['file']}" for f in top]
    lines += ["", "## Same test name repeated in >2 files (copy-paste smell)"]
    lines += [f"- x{len(v)}  `{k[1]}`" for k, v in same_name]
    (out / "report.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()

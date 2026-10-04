#!/usr/bin/env python3
"""Merge test file B into test file A (same package), keeping every test.

  python3 scripts/test_audit/merge_tests.py A_test.dart B_test.dart [--rm]

Imports are unioned; top-level declarations of B are appended (identical duplicates
dropped); B's `main()` body is appended to A's `main()`. Aborts (no write) when a
top-level name collides with a different body, when B's main-level setUp/tearDown
differ from A's, or when relative imports would break (files must share a dir).
Run the merged file, then `dart format`.
"""
import re, subprocess, sys
from pathlib import Path


def split(src):
    m = re.search(r"^(?:Future<void>|void)\s+main\(\)\s*(?:async\s*)?\{", src, re.M)
    head, body_start = src[:m.start()], m.end()
    depth, i = 1, body_start
    while depth:
        c = src[i]
        if c in "'\"":
            q = c; i += 1
            while src[i] != q: i += 2 if src[i] == "\\" else 1
        elif c == "/" and src[i:i+2] == "//": i = src.index("\n", i)
        elif c == "{": depth += 1
        elif c == "}": depth -= 1
        i += 1
    return head, src[body_start:i - 1], src[i:], src[m.start():body_start]


def decls(head):
    imports, rest = [], []
    lines = head.split("\n"); i = 0; buf = []
    while i < len(lines):
        l = lines[i]
        if re.match(r"\s*(import|export)\b", l):
            stmt = l
            while not stmt.rstrip().endswith(";"):
                i += 1; stmt += "\n" + lines[i]
            imports.append(stmt)
        else: buf.append(l)
        i += 1
    return imports, "\n".join(buf).strip()


def blocks(text):
    """split top-level text into declaration chunks separated by blank lines at depth 0 (incl. doc comments)."""
    out, cur, depth = [], [], 0
    for l in text.split("\n"):
        cur.append(l)
        depth += l.count("{") + l.count("(") - l.count("}") - l.count(")")
        if depth <= 0 and l.strip() == "" and any(x.strip() for x in cur):
            out.append("\n".join(cur).strip()); cur = []; depth = 0
    if any(x.strip() for x in cur): out.append("\n".join(cur).strip())
    return [b for b in out if b]


def name_of(b):
    m = re.search(r"^(?:final |const |abstract |base |sealed )*(?:class|mixin|enum|typedef|extension)\s+(\w+)|^[\w<>?,. ]+?\s+(_?\w+)\s*(?:\(|=)", b, re.M)
    return (m.group(1) or m.group(2)) if m else None


def main():
    a_path, b_path = Path(sys.argv[1]), Path(sys.argv[2])
    a, b = a_path.read_text(), b_path.read_text()
    ah, abody, atail, amain = split(a); bh, bbody, btail, _ = split(b)
    ai, arest = decls(ah); bi, brest = decls(bh)
    imports = list(dict.fromkeys(ai + bi))
    ab = blocks(arest + "\n\n"); names = {name_of(x): x for x in ab if name_of(x)}
    add = []
    for blk in blocks(brest + "\n\n"):
        n = name_of(blk)
        if n in names:
            if names[n] != blk: sys.exit(f"ABORT: top-level name collision with different body: {n}")
            continue
        add.append(blk)
    # main-level setUp/tearDown must match
    def hooks(body): return re.findall(r"^  (?:setUp|tearDown|setUpAll|tearDownAll)\(.*?^  \}\);\n", body, re.M | re.S)
    ha, hb = hooks(abody), hooks(bbody)
    for h in hb:
        if h not in ha: sys.exit("ABORT: B has a main-level hook not present in A:\n" + h[:200])
        bbody = bbody.replace(h, "")
    atail_names = {name_of(x) for x in blocks(atail + "\n\n")} | set(names)
    btail_add = []
    for blk in blocks(btail + "\n\n"):
        n = name_of(blk)
        if n in atail_names:
            same = [x for x in blocks(atail + "\n\n") + ab if name_of(x) == n]
            if same and same[0] != blk: sys.exit(f"ABORT: tail name collision with different body: {n}")
            continue
        btail_add.append(blk)
    atail = atail.rstrip() + ("\n\n" + "\n\n".join(btail_add) if btail_add else "") + "\n"
    merged = "\n".join(imports) + "\n\n" + "\n\n".join(x for x in [arest.strip()] + add if x) + "\n\n" + amain + abody.rstrip() + "\n\n  // --- merged from " + b_path.name + " ---\n" + bbody.rstrip() + "\n}" + atail
    a_path.write_text(merged)
    print("merged", b_path.name, "->", a_path.name)
    if "--rm" in sys.argv: subprocess.run(["git", "rm", "-q", "-f", str(b_path)], check=True)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Check that paths / identifiers cited in governing docs still exist in the repo.

  python3 scripts/test_audit/doc_drift.py [doc ...]

For each `backticked` token in the docs:
  * looks like a repo path (has '/' and a known extension or trailing '/')  -> must exist
    (globs and <placeholders> are skipped; generated files tolerated)
  * looks like a Dart identifier (UpperCamelCase, >=6 chars, or lowerCamel with
    a recognizable suffix such as Case/Cubit/Repository/State)  -> must appear
    somewhere in packages/**/lib, packages/**/test, sql/, hasura/ or scripts/
Prints  doc:line  kind  token  for every miss.  Heuristic: review, don't trust blindly.
"""
import re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DOCS = ["AGENTS.md", "CONTEXT.md", "DEV_GUIDELINES.md", "DEVELOPMENT.md", "README.md",
                ".claude/CLAUDE.md", "docs/README.md", "docs/Tentura_current_status_quo.md",
                "docs/test-coverage-misses.md", "docs/local-integration-tests.md"] + \
    sorted(str(p.relative_to(ROOT)) for p in (ROOT / ".cursor/rules").glob("*.mdc")) + \
    sorted(str(p.relative_to(ROOT)) for p in (ROOT / ".claude/skills").glob("*/SKILL.md"))
PATH_EXT = r"(?:dart|md|mdc|sh|py|sql|yaml|yml|json|arb|toml|graphql|html|js|env|txt)"
TOKEN = re.compile(r"`([^`\n]+)`")
GEN = re.compile(r"\.(g|gr|gql|freezed|config|schema|data|var|req)\.dart$|/_g/|/l10n/")
IDENT = re.compile(r"^[A-Z][A-Za-z0-9]{5,}$|^[a-z]+[A-Z][A-Za-z0-9]*(?:Case|Cubit|Repository|State|Service|Port|Manager|Controller)$")

def corpus():
    out = subprocess.run(["git", "ls-files", "packages", "sql", "hasura", "scripts", "lib", "test",
                          ".github", "pubspec.yaml"], cwd=ROOT, capture_output=True, text=True).stdout.split()
    txt = []
    for f in out:
        if f.endswith((".dart", ".sql", ".yaml", ".yml", ".sh", ".py", ".json", ".graphql", ".arb")):
            try: txt.append((ROOT / f).read_text(errors="replace"))
            except OSError: pass
    return "\n".join(txt)

def exists(tok, tracked, base=""):
    t = tok.strip()
    if t.startswith("../") and base:
        t = str((Path(base) / t).resolve().relative_to(ROOT)) if (ROOT / base / t).resolve().is_relative_to(ROOT) else t
    t = t[2:] if t.startswith("./") else t
    t = re.sub(r"[:#]\d+(-\d+)?$", "", t)          # file.dart:12
    if any(c in t for c in "*<>{}$[]|") or " " in t or t.startswith(("/", "package:", "...", "dart:")) or ".../" in t: return True
    if t.endswith("/"): return any(f.startswith(t) or ("/" + t) in f for f in tracked)
    return t in tracked or (base and (base + "/" + t) in tracked) or any(f.endswith("/" + t) for f in tracked) or bool(GEN.search(t))

def main():
    docs = sys.argv[1:] or DEFAULT_DOCS
    tracked = set(subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True).stdout.split())
    haystack = corpus()
    miss = 0
    for d in docs:
        p = ROOT / d
        if not p.exists(): print(f"{d}: DOC MISSING"); continue
        for i, line in enumerate(p.read_text().splitlines(), 1):
            if "drift-ok" in line: continue
            for tok in TOKEN.findall(line):
                if re.search(rf"[\w\-./]+\.{PATH_EXT}(?:[:#]\d+(?:-\d+)?)?$", tok) or (tok.endswith("/") and "/" in tok[:-1]):
                    if not exists(tok, tracked, str(Path(d).parent) if "/" in d else ""): print(f"{d}:{i}\tPATH\t{tok}"); miss += 1
                elif IDENT.match(tok) and tok not in haystack:
                    print(f"{d}:{i}\tIDENT\t{tok}"); miss += 1
    print(f"-- {miss} unresolved references", file=sys.stderr)

if __name__ == "__main__":
    main()

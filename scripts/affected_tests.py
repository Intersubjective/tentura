#!/usr/bin/env python3
"""Tests a change can reach: transitive import-graph test selection.

A test file is selected when it imports a changed Dart file directly or
through any chain of `import` / `export` / `part` directives (conditional
imports included), across the workspace packages. Dart only compiles what a
test imports, so this never misses a Dart change. It can miss non-Dart
inputs (ARB, GraphQL documents, fixtures, pubspec, test config) and runtime
reads of other files; these rules cover those:

  * an ARB file (l10n/*.arb) selects the files that name a key whose text or
    metadata changed (the generated L10n getter has the key's name), the
    test files that read ARB files at runtime (they name `.arb` or `l10n/app_`)
    and the classes that implement or extend L10n, and what imports them.
    An ARB file that is added, removed, not valid JSON or changes
    `@@locale` selects the whole package;
  * a GraphQL document (lib/**/x.graphql) counts as a change to the Ferry
    files generated from it (lib/**/_g/x.*.gql.dart). From those files the
    graph is followed without passing through `_g/serializers.gql.dart`: it
    imports every generated file and is imported by all of them, but it only
    registers serializers, so it does not carry one document's change to
    code that uses other documents. (A Dart change, such as a custom
    serializer, does go through it.) Without generated files the whole
    package is selected;
  * a test fixture (non-Dart file under test/) counts as a change to every
    Dart file under test/ that names it (its basename), when one does;
    otherwise the whole package;
  * any other non-Dart file under the package's lib/, integration_test/ or
    assets/ selects the whole package;
  * env/*.env, test/flutter_test_config.dart, dart_test.yaml, build.yaml,
    l10n.yaml or analysis_options.yaml of the package select the whole
    package;
  * pubspec.yaml of the package or of the workspace root selects the whole
    package unless only its `version:` line changed; pubspec.lock selects
    every package;
  * server: a migration (lib/data/database/migration/**) adds every
    pg-tagged test;
  * anything changed outside the package adds the package's tests tagged
    `repo-files` (they read other packages, docs, scripts; CI does the same,
    scripts/ci_changes.py).

Usage (from anywhere):
  scripts/affected_tests.py <package-dir> [--base REV]
      Changed files = working tree + untracked vs REV (default HEAD). Prints
      the selected `*_test.dart` paths relative to the package, one per line;
      the reason for a whole-package fallback goes to stderr.
  scripts/affected_tests.py --replay [N] [--repo PATH]
      Runs the selector over the last N (default 300) non-merge commits with
      today's graph and prints, per package, the p25 / p50 / p75 / mean share
      of the package's test files selected over the commits that touch the
      package or a shared input (whole-package fallbacks counted as 100%),
      and how many commits fell back and why.
"""

from __future__ import annotations

import argparse
import collections
import difflib
import json
import os
import re
import statistics
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

REPO = Path(__file__).resolve().parent.parent

# Package name -> directory (relative to the repo root). `tentura_root` is the
# workspace root package; both apps import it.
PACKAGES = {
    "tentura_root": ".",
    "tentura": "packages/client",
    "tentura_server": "packages/server",
    "force_directed_graphview": "packages/force_directed_graphview",
    "image_cropper_for_web": "packages/image_cropper_for_web",
    "web_socket_client": "packages/web_socket_client",
    "ferry_generator": "packages/ferry_generator",
    "tentura_lints": "packages/tentura_lints",
}
SELECTABLE = ("packages/client", "packages/server")

DIRECTIVE = re.compile(r"""^\s*(?:import|export|part)\s+['"]([^'"]+)['"]""", re.M)
CONDITIONAL = re.compile(r"""\bif\s*\([^)]*\)\s*['"]([^'"]+)['"]""")
PG_TAG = re.compile(r"""['"]pg['"]""")
REPO_FILES_TAG = re.compile(r"""['"]repo-files['"]""")
IDENTIFIER = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")
ARB_READER = re.compile(r"\.arb\b|l10n/app_")
L10N_SUBTYPE = re.compile(r"\b(?:implements|extends)\s+L10n\b")
SKIP_DIRS = {".dart_tool", "build", ".git", "node_modules", ".pub-cache"}

WHOLE_PACKAGE_CONFIG = {
    "dart_test.yaml",
    "build.yaml",
    "l10n.yaml",
    "analysis_options.yaml",
    "test/flutter_test_config.dart",
}
MIGRATIONS = "lib/data/database/migration/"
GENERATED_L10N = "lib/ui/l10n/"
SERIALIZERS_HUB = "/_g/serializers.gql.dart"

# (path) -> the file's text before / after the change; None when absent.
Version = Callable[[str], "str | None"]


def _resolve(src: str, uri: str) -> str | None:
    if uri.startswith("dart:"):
        return None
    if uri.startswith("package:"):
        name, _, rest = uri[len("package:"):].partition("/")
        pkg = PACKAGES.get(name)
        return os.path.normpath(f"{pkg}/lib/{rest}") if pkg is not None else None
    if ":" in uri:
        return None
    return os.path.normpath(os.path.join(os.path.dirname(src), uri))


class Graph:
    """Reverse Dart import graph of the workspace (imported -> importers)."""

    def __init__(self, root: Path):
        self.root = root
        self.importers: dict[str, set[str]] = collections.defaultdict(set)
        self.files: set[str] = set()
        for pkg in PACKAGES.values():
            base = root / pkg
            for subdir in ("lib", "test", "integration_test", "bin", "tool"):
                top = base / subdir
                if not top.is_dir():
                    continue
                for d, dirs, fs in os.walk(top):
                    dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
                    for f in fs:
                        if f.endswith(".dart"):
                            self.files.add(os.path.relpath(os.path.join(d, f), root))
        self._text_cache: dict[str, str] = {}
        self._identifier_cache: dict[str, frozenset[str]] = {}
        for f in self.files:
            text = self.text(f)
            for uri in DIRECTIVE.findall(text) + CONDITIONAL.findall(text):
                target = _resolve(f, uri)
                if target:
                    self.importers[target].add(f)

    def text(self, f: str) -> str:
        if f not in self._text_cache:
            self._text_cache[f] = (self.root / f).read_text(encoding="utf-8", errors="ignore")
        return self._text_cache[f]

    def identifiers(self, f: str) -> frozenset[str]:
        if f not in self._identifier_cache:
            self._identifier_cache[f] = frozenset(IDENTIFIER.findall(self.text(f)))
        return self._identifier_cache[f]

    def tests(self, pkg: str) -> set[str]:
        prefix = f"{pkg}/test/"
        return {f for f in self.files if f.startswith(prefix) and f.endswith("_test.dart")}

    def tagged(self, pkg: str, tag: re.Pattern[str]) -> set[str]:
        return {t for t in self.tests(pkg) if tag.search(self.text(t))}

    def reach(self, changed: set[str], skip: Callable[[str], bool] = lambda _: False) -> set[str]:
        """[changed] plus every file that imports one of them, transitively,
        never passing through a file for which [skip] is true."""
        seen, stack = set(changed), list(changed)
        while stack:
            for importer in self.importers.get(stack.pop(), ()):
                if importer not in seen and not skip(importer):
                    seen.add(importer)
                    stack.append(importer)
        return seen


@dataclass
class Selection:
    tests: set[str] = field(default_factory=set)
    # Why the whole package was selected; empty when the graph decided.
    fallbacks: list[str] = field(default_factory=list)


def _owner(path: str) -> str:
    """The package directory [path] belongs to (deepest match), or `.`."""
    best = None
    for pkg in PACKAGES.values():
        if pkg != "." and path.startswith(pkg + "/"):
            best = pkg
    return best or "."


def _pubspec_only_version(before: str | None, after: str | None) -> bool:
    """Whether a pubspec change touches only its `version:` line."""
    if before is None or after is None:
        return False
    changed = [
        line[1:]
        for line in difflib.unified_diff(before.splitlines(), after.splitlines(), lineterm="")
        if line[:1] in "+-" and not line.startswith(("+++", "---"))
    ]
    return bool(changed) and all(
        line.strip() == "" or line.startswith("version:") for line in changed
    )


def _arb_changed_keys(before: str | None, after: str | None) -> set[str] | None:
    """L10n getter names whose ARB text or metadata changed; None when the
    change is not a key-level edit of an existing locale file."""
    try:
        old = json.loads(before) if before is not None else None
        new = json.loads(after) if after is not None else None
    except ValueError:
        return None
    if not isinstance(old, dict) or not isinstance(new, dict):
        return None
    if old.get("@@locale") != new.get("@@locale"):
        return None
    return {
        key.lstrip("@")
        for key in old.keys() | new.keys()
        if not key.startswith("@@") and old.get(key) != new.get(key)
    }


def _graphql_outputs(graph: Graph, path: str) -> set[str]:
    stem = os.path.basename(path)[: -len(".graphql")]
    prefix = os.path.join(os.path.dirname(path), "_g", stem + ".")
    return {f for f in graph.files if f.startswith(prefix) and f.endswith(".gql.dart")}


def select(
    graph: Graph,
    pkg: str,
    changed: list[str],
    before: Version,
    after: Version,
) -> Selection:
    """Tests of [pkg] (paths relative to the repo) that [changed] can reach."""
    sel = Selection()
    all_tests = graph.tests(pkg)
    seeds: set[str] = set()
    gql_seeds: set[str] = set()
    arb_keys: set[str] = set()
    arb_changed = False
    outside = False

    def whole(reason: str) -> None:
        sel.fallbacks.append(reason)

    for path in changed:
        owner = _owner(path)
        rel = path[len(pkg) + 1:] if owner == pkg else None
        name = os.path.basename(path)

        # Shared inputs of every package.
        if path == "pubspec.lock":
            whole("pubspec.lock")
            continue
        if path == "pubspec.yaml":
            if not _pubspec_only_version(before(path), after(path)):
                whole("root pubspec.yaml")
            continue

        if path.endswith(".dart"):
            seeds.add(path)
            if rel is None:
                outside = True
            elif rel == "test/flutter_test_config.dart":
                whole(rel)
            elif pkg == "packages/server" and rel.startswith(MIGRATIONS):
                # The schema changed under every pg test, imported or not.
                sel.tests |= graph.tagged(pkg, PG_TAG)
            continue

        if rel is None:
            # A non-Dart file of another package or of the repo (docs,
            # scripts, ARB of the client for the server, ...).
            outside = True
            continue

        if rel == "pubspec.yaml":
            if not _pubspec_only_version(before(path), after(path)):
                whole("pubspec.yaml")
        elif rel in WHOLE_PACKAGE_CONFIG or rel.startswith("env/"):
            whole(rel)
        elif rel.startswith("l10n/") and rel.endswith(".arb"):
            keys = _arb_changed_keys(before(path), after(path))
            if keys is None:
                whole(f"{rel} (locale added, removed or not valid JSON)")
            else:
                arb_changed = True
                arb_keys |= keys
        elif rel.startswith("lib/") and rel.endswith(".graphql"):
            outputs = _graphql_outputs(graph, path)
            if outputs:
                gql_seeds |= outputs
            else:
                whole(f"{rel} (no generated Ferry files)")
        elif rel.startswith("test/"):
            naming = {
                f for f in graph.files
                if f.startswith(f"{pkg}/test/") and name in graph.text(f)
            }
            if naming:
                seeds |= naming
            else:
                whole(f"{rel} (fixture named by no test file)")
        elif rel.startswith(("lib/", "integration_test/", "assets/")):
            whole(rel)
        # Anything else of the package (web/, android/, tool/, README, ...)
        # is not a test input.

    if sel.fallbacks:
        sel.tests = set(all_tests)
        return sel
    if arb_changed:
        generated = f"{pkg}/{GENERATED_L10N}"
        for f in graph.files:
            if not f.startswith(f"{pkg}/") or f.startswith(generated):
                continue
            text = graph.text(f)
            if (
                (f.startswith(f"{pkg}/test/") and ARB_READER.search(text))
                or L10N_SUBTYPE.search(text)
                or not arb_keys.isdisjoint(graph.identifiers(f))
            ):
                seeds.add(f)
    reached = graph.reach(seeds)
    reached |= graph.reach(gql_seeds, skip=lambda f: f.endswith(SERIALIZERS_HUB))
    sel.tests |= reached & all_tests
    if outside:
        sel.tests |= graph.tagged(pkg, REPO_FILES_TAG)
    return sel


def _git(*args: str, cwd: Path, check: bool = True) -> str:
    result = subprocess.run(
        ["git", *args], cwd=cwd, capture_output=True, text=True, check=check
    )
    return result.stdout if result.returncode == 0 else ""


def _show(root: Path, rev: str, path: str) -> str | None:
    """[path] at [rev], or None when it does not exist there."""
    result = subprocess.run(
        ["git", "show", f"{rev}:{path}"], cwd=root, capture_output=True, text=True
    )
    return result.stdout if result.returncode == 0 else None


def _working_tree_changes(root: Path, base: str) -> list[str]:
    tracked = _git("diff", "--name-only", base, cwd=root).splitlines()
    untracked = _git("ls-files", "--others", "--exclude-standard", cwd=root).splitlines()
    return sorted({p for p in tracked + untracked if p})


def _read(root: Path, path: str) -> str | None:
    try:
        return (root / path).read_text(encoding="utf-8")
    except OSError:
        return None


def _quantile(sorted_shares: list[float], p: float) -> float:
    return sorted_shares[int(p * (len(sorted_shares) - 1))]


def _replay(root: Path, n: int) -> None:
    graph = Graph(root)
    log = _git(
        "log", "--no-merges", "-n", str(n), "--name-only", "--format=@@%H", cwd=root
    )
    commits: list[tuple[str, list[str]]] = []
    for line in log.splitlines():
        if line.startswith("@@"):
            commits.append((line[2:], []))
        elif line.strip() and commits:
            commits[-1][1].append(line.strip())
    print(f"replay: {len(commits)} non-merge commits, today's graph")
    for pkg in SELECTABLE:
        total = len(graph.tests(pkg))
        shares: list[float] = []
        reasons: collections.Counter[str] = collections.Counter()
        fell_back = 0
        for sha, changed in commits:
            if not any(
                p.startswith(pkg + "/") or p in ("pubspec.yaml", "pubspec.lock")
                or p.startswith("lib/")
                for p in changed
            ):
                continue
            sel = select(
                graph, pkg, changed,
                lambda path, sha=sha: _show(root, f"{sha}^", path),
                lambda path, sha=sha: _show(root, sha, path),
            )
            shares.append(len(sel.tests) / total)
            if sel.fallbacks:
                fell_back += 1
                for reason in sel.fallbacks:
                    reasons[_reason_key(reason)] += 1
        if not shares:
            print(f"{pkg}: no commits touch it")
            continue
        shares.sort()
        print(
            f"{pkg}: {total} test files, {len(shares)} commits touching it — "
            f"selected p25 {_quantile(shares, .25):.0%} "
            f"p50 {_quantile(shares, .5):.0%} p75 {_quantile(shares, .75):.0%} "
            f"mean {statistics.mean(shares):.0%}; whole-package fallback in "
            f"{fell_back} commits"
            + (": " + ", ".join(f"{k} ×{v}" for k, v in reasons.most_common()) if reasons else "")
        )


def _reason_key(reason: str) -> str:
    """Groups fallback reasons for the replay summary."""
    base = reason.split(" (")[0]
    if base in WHOLE_PACKAGE_CONFIG or "pubspec" in base:
        return base
    if base.startswith("env/"):
        return "env/*.env"
    if base.startswith("l10n/"):
        return "ARB locale added / removed / invalid"
    if base.startswith("test/"):
        return "unnamed test fixture"
    if base.startswith(("lib/", "assets/", "integration_test/")):
        return "non-Dart file under " + base.split("/")[0] + "/"
    return base


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("package", nargs="?", help="packages/client or packages/server")
    ap.add_argument("--base", default="HEAD")
    ap.add_argument("--replay", nargs="?", type=int, const=300)
    ap.add_argument("--repo", default=str(REPO))
    args = ap.parse_args()
    root = Path(args.repo).resolve()
    if args.replay is not None:
        _replay(root, args.replay)
        return 0
    pkg = (args.package or "").rstrip("/")
    if pkg not in SELECTABLE:
        ap.error(f"package must be one of {', '.join(SELECTABLE)}")
    changed = _working_tree_changes(root, args.base)
    graph = Graph(root)
    sel = select(
        graph, pkg, changed,
        lambda path: _show(root, args.base, path),
        lambda path: _read(root, path),
    )
    for reason in sel.fallbacks:
        print(f"affected_tests: whole {pkg}: {reason} changed", file=sys.stderr)
    for t in sorted(sel.tests):
        print(t[len(pkg) + 1:])
    return 0


if __name__ == "__main__":
    sys.exit(main())

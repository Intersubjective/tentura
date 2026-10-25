#!/usr/bin/env python3
"""Generate test bundles: a few entrypoints that each import many test files.

`flutter test` / `dart test` compile, spawn and load every test file on its
own. On a 4-vCPU runner that per-file overhead was more than half of a client
shard (client-b: 577 s of loading vs 462 s of tests; bundled, the shard went
from 541 s to ~75 s) and a third of the server's non-pg run (161 s -> 104 s).
A bundle declares each imported file's tests inside `group('<path>', ...)`,
so one compile and one isolate / flutter_tester process serve a whole chunk
of files.

Usage (from anywhere):
  scripts/gen_test_bundles.py <package-dir> [--chunks N] [--balance FAMILY]
                              [test paths...]

Writes `<package-dir>/test/_bundle/bundle_<i>_test.dart` (gitignored) and
prints, one per line, the files to pass to `dart test` / `flutter test`: the
bundles plus every test file that has to keep running on its own.

The test runner starts suites in the order given, a few at a time, so a
shard's wall time is set by how its suites pack into those slots. With
--balance FAMILY (durations from scripts/ci_test_durations.json, as in
scripts/ci_select_tests.py) the files are dealt into bundles by measured
duration rather than by count, and the entrypoints are printed longest
first, so a long standalone suite does not start last and run on alone.

A file runs on its own (is not bundled) when it:
  * has an async `main` (declares tests after an `await`, which a group body
    cannot do) or no `void main()` at all;
  * carries a file-level annotation other than `@Tags` / `@Timeout` on a
    `package:test` package (`@TestOn`, `@Skip`, `@OnPlatform`, `@Retry`), or
    any file-level annotation on a Flutter package (flutter_test's `group`
    takes no tags or timeout);
  * is tagged `pg` (server: per-suite tags drive the MeritRank suite lock);
  * compares goldens (golden paths resolve against the entrypoint's location);
  * is listed in `<package-dir>/test/bundle_exclude.txt` (one path per line,
    relative to the package, `#` comments allowed) because it leaks or
    depends on process-wide state that another file in the same isolate
    would see.

Per-file isolation the bundle restores: every file's group ends with
`_resetBetweenFiles`, which puts back what a fresh isolate per file used to
give — an empty GetIt (when the package uses get_it; otherwise "Type X is
already registered inside GetIt") and, for Flutter, the default test view and
platform-dispatcher test values (a file that resizes the view without
resetting it moves the next file's `tapAt` targets).

Locally, keep running plain per-file `flutter test` / `dart test`; bundles are
a CI-only optimisation and the per-file runs stay the reference.
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

from ci_select_tests import DURATIONS, Durations, pack, weights

BUNDLE_DIR = Path("test") / "_bundle"
EXCLUDE_FILE = Path("test") / "bundle_exclude.txt"

SYNC_MAIN = re.compile(r"^void main\(\)", re.MULTILINE)
GOLDEN = re.compile(r"\bmatchesGoldenFile\b")
# File-level annotations sit before the first import/library/part directive.
DIRECTIVE = re.compile(r"^(import|export|library|part)\b", re.MULTILINE)
ANNOTATION = re.compile(r"^@(\w+)\s*\(", re.MULTILINE)


def _balanced_args(text: str, open_paren: int) -> str:
    """The text between the parenthesis at [open_paren] and its partner."""
    depth = 0
    for i in range(open_paren, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return text[open_paren + 1 : i]
    raise ValueError("unbalanced annotation")


def file_annotations(source: str) -> dict[str, str]:
    """Maps each file-level annotation name to its argument text."""
    first_directive = DIRECTIVE.search(source)
    header = source[: first_directive.start()] if first_directive else source
    found = {}
    for match in ANNOTATION.finditer(header):
        found[match.group(1)] = _balanced_args(header, match.end() - 1).strip()
    return found


def read_excludes(package: Path) -> set[str]:
    path = package / EXCLUDE_FILE
    if not path.is_file():
        return set()
    entries = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            entries.add(line)
    return entries


def group_options(annotations: dict[str, str], flutter: bool) -> str | None:
    """Named `group(...)` arguments for the file, or None if not bundleable."""
    if flutter:
        return "" if not annotations else None
    options = []
    for name, args in annotations.items():
        if name == "Tags":
            options.append(f"tags: {args}")
        elif name == "Timeout":
            options.append(f"timeout: Timeout({args})")
        else:
            return None
    return "".join(f", {option}" for option in options)


def collect(package: Path, paths: list[str]) -> list[Path]:
    files: set[Path] = set()
    for raw in paths:
        target = package / raw
        if target.is_file():
            files.add(target)
        elif target.is_dir():
            files.update(target.rglob("*_test.dart"))
        else:
            raise SystemExit(f"gen_test_bundles: no such test path: {raw}")
    bundle_dir = package / BUNDLE_DIR
    return sorted(f for f in files if bundle_dir not in f.parents)


def reset_function(flutter: bool, uses_get_it: bool) -> list[str]:
    """`_resetBetweenFiles`: what a fresh isolate per file used to give."""
    body = []
    if uses_get_it:
        # Singletons a file registers and never unregisters.
        body.append("  await GetIt.I.reset();")
    if flutter:
        # Test view size / pixel ratio, text scale, locale, brightness...
        # set by one file without a matching reset. Not the binding's
        # setSurfaceSize override: that call only works inside a test, so
        # each file resets its own (test/architecture/
        # test_surface_size_reset_test.dart, #754).
        body += [
            "  if (BindingBase.debugBindingType() != null) {",
            "    final binding = TestWidgetsFlutterBinding.instance;",
            "    binding.platformDispatcher.clearAllTestValues();",
            "    for (final view in binding.platformDispatcher.views) {",
            "      view.reset();",
            "    }",
            "  }",
        ]
    return ["Future<void> _resetBetweenFiles() async {", *body, "}", ""]


def chunk(items: list, count: int) -> list[list]:
    count = max(1, min(count, len(items)))
    size, extra = divmod(len(items), count)
    out, start = [], 0
    for i in range(count):
        end = start + size + (1 if i < extra else 0)
        out.append(items[start:end])
        start = end
    return out


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("package", type=Path)
    parser.add_argument("paths", nargs="*", default=["test"])
    parser.add_argument("--chunks", type=int, default=4)
    parser.add_argument("--balance", metavar="FAMILY")
    parser.add_argument("--durations", type=Path, default=DURATIONS)
    # Intermixed: `<package> --chunks N <paths...>` (Python < 3.12 rejects
    # positionals after an option with plain parse_args).
    args = parser.parse_intermixed_args(argv)

    package: Path = args.package.resolve()
    pubspec = (package / "pubspec.yaml").read_text(encoding="utf-8")
    flutter = re.search(r"^\s+flutter_test:", pubspec, re.MULTILINE) is not None
    test_import = (
        "package:flutter_test/flutter_test.dart" if flutter else "package:test/test.dart"
    )
    # Workspace packages resolve get_it from the root pubspec.
    root_pubspec = (package.parent.parent / "pubspec.yaml")
    uses_get_it = any(
        re.search(r"^\s+get_it:", f.read_text(encoding="utf-8"), re.MULTILINE)
        for f in (package / "pubspec.yaml", root_pubspec)
        if f.is_file()
    )
    excludes = read_excludes(package)

    bundled: list[tuple[str, str]] = []
    standalone: list[str] = []
    for file in collect(package, args.paths):
        rel = file.relative_to(package).as_posix()
        source = file.read_text(encoding="utf-8")
        annotations = file_annotations(source)
        options = group_options(annotations, flutter)
        if (
            rel in excludes
            or options is None
            or not SYNC_MAIN.search(source)
            or GOLDEN.search(source)
            or re.search(r"['\"]pg['\"]", annotations.get("Tags", ""))
        ):
            standalone.append(rel)
        else:
            bundled.append((rel, options))

    weight: dict[str, float] = {}
    if args.balance:
        table = Durations(args.durations).table(args.balance)
        rels = [rel for rel, _ in bundled] + standalone
        by_path = weights([str(package / rel) for rel in rels], table)
        weight = {rel: by_path[str(package / rel)] for rel in rels}
        options_of = dict(bundled)
        chunks = [
            sorted((rel, options_of[rel]) for rel in members)
            for members in pack({rel: weight[rel] for rel, _ in bundled},
                                max(1, min(args.chunks, len(bundled))))[0]
        ] if bundled else []
    else:
        chunks = chunk(bundled, args.chunks) if bundled else []

    bundle_dir = package / BUNDLE_DIR
    shutil.rmtree(bundle_dir, ignore_errors=True)
    entrypoints = []
    if bundled:
        bundle_dir.mkdir(parents=True)
        for index, members in enumerate(chunks):
            lines = [
                "// GENERATED by scripts/gen_test_bundles.py for CI. Do not edit.",
                "",
                *(["import 'package:flutter/foundation.dart';"] if flutter else []),
                *(["import 'package:get_it/get_it.dart';"] if uses_get_it else []),
                f"import '{test_import}';",
                "",
            ]
            for n, (rel, _) in enumerate(members):
                # The bundle lives in test/_bundle/, so `..` is test/.
                lines.append(f"import '../{Path(rel).relative_to('test').as_posix()}' as t{n};")
            lines += ["", "void main() {"]
            for n, (rel, options) in enumerate(members):
                lines += [
                    f"  group('{rel}', () {{",
                    "    tearDownAll(_resetBetweenFiles);",
                    f"    t{n}.main();",
                    f"  }}{options});",
                ]
            lines += ["}", "", *reset_function(flutter, uses_get_it)]
            name = f"bundle_{index}_test.dart"
            (bundle_dir / name).write_text("\n".join(lines), encoding="utf-8")
            entrypoints.append((BUNDLE_DIR / name).as_posix())
            weight[entrypoints[-1]] = sum(weight.get(rel, 0.0) for rel, _ in members)

    print(
        f"gen_test_bundles: {len(bundled)} files in {len(entrypoints)} bundles, "
        f"{len(standalone)} standalone",
        file=sys.stderr,
    )
    ordered = entrypoints + standalone
    if args.balance:
        ordered.sort(key=lambda e: (-weight[e], e))
    print("\n".join(ordered))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

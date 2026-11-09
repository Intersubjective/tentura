#!/usr/bin/env python3
"""Tests a change can reach: transitive import-graph test selection.

A test file is selected when it imports a changed Dart file directly or
through any chain of `import` / `export` / `part` directives (conditional
imports included), across the workspace packages; every Dart file of a
package (lib/, test/, hook/, tool/, bin/, ...) is in the graph. Dart only
compiles what a test imports, so the graph finds every test that compiles a
changed Dart file. It cannot see a test that reads files at runtime, nor
non-Dart inputs (ARB, GraphQL documents, fixtures, web files, pubspec, test
config); these rules cover those:

  * source readers: every Dart file under test/architecture/ and every Dart
    file under test/ that reads the package's sources through dart:io (it
    calls `File(` / `Directory(` and has a string naming lib/, test/, hook/,
    bin/, tool/ or integration_test/), with what imports them, are selected
    when a Dart file of the package or a file under its lib/ changes under a
    path the reader names. Only package-relative strings name one: a string
    that starts with lib/, test/, hook/, bin/, tool/ or integration_test/,
    or with an interpolation of the package root (`${packageRoot}`,
    `$root/`, `${_clientRoot.path}/`: its expression says root or package)
    followed by one of them, cut at the next interpolation (`'lib/features'`
    -> `lib/features`). Another package's path or a temp dir's does not
    name one; a reader left with no such string takes every change;

  * an ARB file (l10n/*.arb) selects the files that name a key whose text or
    metadata changed (the generated L10n getter has the key's name), the
    test files that read ARB files at runtime (they name `.arb` or `l10n/app_`)
    and the classes that implement or extend L10n, and what imports them.
    An ARB file that is added, removed, not valid JSON or changes
    `@@locale` selects the whole package;
  * the GraphQL schema (lib/**/schema.graphql) selects the files that name
    it, plus the Ferry operation groups and hand-written files that use what
    changed in it, definition by definition (see _schema_changes and
    _schema_seeds for what Ferry generates and how each change is matched);
    the graph is then followed without passing through the two Ferry files
    that list every type (schema.schema.gql.dart, serializers.gql.dart). A
    change no definition owns (a `schema {}` or directive definition, text
    that does not parse, the file added or removed) counts as a change to
    every Ferry file generated in the package instead. Without generated
    files the whole package is selected, either way;
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
  * any other non-Dart file under the package's lib/, integration_test/,
    assets/, fonts/ or images/ selects the whole package;
  * any other non-Dart file of the package (web/, android/, README, ...)
    counts as a change to every Dart file of the package that names its
    basename outside a whole-line comment; a file under web/ that no Dart
    file names selects the whole package, any other selects nothing;
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
import functools
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
SKIP_DIRS = {"node_modules"}
# Directories skipped at a package's top level only (hook/build/ is source).
SKIP_TOP_DIRS = {"build", "packages"}
# A source reader: a dart:io File / Directory and a string naming a source dir.
IO_CALL = re.compile(r"\b(?:File|Directory)\s*\(")
STRING = re.compile(r"""['"]([^'"\n]*)['"]""")
# A package-relative source path in a string: at its start, or after an
# interpolation of the package root (its expression says root or package).
SOURCE_DIR = re.compile(
    r"^(?:(?:\$\{(?P<expr>[^}]*)\}|\$(?P<name>\w+))/?)?"
    r"(?P<path>(?:lib|test|hook|bin|tool|integration_test)(?:/.*)?)$"
)
ROOT_EXPRESSION = re.compile(r"root|package", re.I)
SOURCE_PATH = re.compile(
    r"""['"](?!package:|dart:)(?:[^'"\n]*[/}])?"""
    r"""(?:lib|test|hook|bin|tool|integration_test)(?:/|['"])"""
)

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
SCHEMA_HUB = "/_g/schema.schema.gql.dart"
# Ferry's generated files and the two that list every type (with their
# built_value parts).
FERRY_FILE = re.compile(r"/_g/([^/.]+)\.[^/]*gql(?:\.g)?\.dart$")
FERRY_HUBS = ("/_g/serializers.gql", "/_g/schema.schema.gql")
NAME_NODE = re.compile(r"NameNode\(\s*value:\s*'([^']*)'")
# A type reference in an .ast file (a variable's type, a fragment's type
# condition); a bare NameNode there may be a field or argument name.
NAMED_TYPE = re.compile(
    r"NamedTypeNode\(\s*name:\s*(?:_i\d+\.)?NameNode\(\s*value:\s*'([^']*)'"
)

# SDL top-level definitions; `schema` and `directive` cannot be attributed.
SDL_DEFINITION = re.compile(
    r"^(extend[ \t]+)?(type|input|enum|scalar|interface|union|schema|directive)\b[ \t]*@?(\w*)",
    re.M,
)
SDL_MEMBER = re.compile(r"^\s*([A-Za-z_]\w*)")

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
            for d, dirs, fs in os.walk(base):
                top = Path(d) == base
                dirs[:] = [
                    x for x in dirs
                    if not x.startswith(".") and x not in SKIP_DIRS
                    and not (top and x in SKIP_TOP_DIRS)
                ]
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

    @functools.cache
    def code(self, f: str) -> str:
        """[f] without its whole-line comments."""
        return "\n".join(
            line for line in self.text(f).splitlines() if not line.lstrip().startswith("//")
        )

    @functools.cache
    def strings(self, f: str) -> frozenset[str]:
        """Contents of the one-line string literals of [f]."""
        return frozenset(STRING.findall(self.text(f)))

    def identifiers(self, f: str) -> frozenset[str]:
        if f not in self._identifier_cache:
            self._identifier_cache[f] = frozenset(IDENTIFIER.findall(self.text(f)))
        return self._identifier_cache[f]

    def tests(self, pkg: str) -> set[str]:
        prefix = f"{pkg}/test/"
        return {f for f in self.files if f.startswith(prefix) and f.endswith("_test.dart")}

    def tagged(self, pkg: str, tag: re.Pattern[str]) -> set[str]:
        return {t for t in self.tests(pkg) if tag.search(self.text(t))}

    @functools.cache
    def package_files(self, pkg: str) -> frozenset[str]:
        return frozenset(f for f in self.files if _owner(f) == pkg)

    @functools.cache
    def reader_prefixes(self, pkg: str) -> dict[str, tuple[str, ...]]:
        """Source readers of [pkg] -> the package-relative path prefixes they
        name; an empty tuple means every path."""
        out = {}
        for f in self.source_readers(pkg):
            prefixes = set()
            for line in self.text(f).splitlines():
                if DIRECTIVE.match(line):
                    continue
                for literal in STRING.findall(line):
                    m = SOURCE_DIR.match(literal)
                    if not m:
                        continue
                    root = m.group("expr") or m.group("name")
                    if root is not None and not ROOT_EXPRESSION.search(root):
                        continue  # a temp dir or another tree, not the package
                    # From the dir to the next interpolation.
                    prefixes.add(m.group("path").split("$", 1)[0].rstrip("/"))
            out[f] = tuple(sorted(prefixes))
        return out

    def readers_of(self, pkg: str, rels: set[str]) -> set[str]:
        """Source readers of [pkg] that name a prefix of one of [rels]."""
        return {
            f for f, prefixes in self.reader_prefixes(pkg).items()
            if not prefixes or any(r.startswith(x) for r in rels for x in prefixes)
        }

    @functools.cache
    def source_readers(self, pkg: str) -> frozenset[str]:
        """Dart files under [pkg]/test/ that read the package's sources at
        runtime (see the module docstring)."""
        out = set()
        for f in self.files:
            if not f.startswith(f"{pkg}/test/"):
                continue
            if f.startswith(f"{pkg}/test/architecture/"):
                out.add(f)
                continue
            text = self.text(f)
            if IO_CALL.search(text) and any(
                SOURCE_PATH.search(line)
                for line in text.splitlines()
                if not DIRECTIVE.match(line)
            ):
                out.add(f)
        return frozenset(out)

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


def _ferry_hub(f: str) -> bool:
    """The Ferry files that list every type (and their built_value parts):
    following them would select every GraphQL user for any one change."""
    return any(hub in f for hub in FERRY_HUBS)


def _sdl_strip(sdl: str) -> str:
    '''[sdl] without comments and descriptions. A description is a string
    (`"..."` or `"""..."""`) that starts its line; any other string (a
    default value, a directive argument) is kept as written.'''
    out: list[str] = []
    i, n, line_blank = 0, len(sdl), True
    while i < n:
        if sdl.startswith('"""', i):
            end = sdl.find('"""', i + 3)
            end = n if end < 0 else end + 3
        elif sdl[i] == '"':
            end = i + 1
            while end < n and sdl[end] not in '"\n':
                end += 2 if sdl[end] == "\\" else 1
            end = min(end + 1, n)
        elif sdl[i] == "#":
            end = sdl.find("\n", i)
            i = n if end < 0 else end
            continue
        else:
            out.append(sdl[i])
            if sdl[i] == "\n":
                line_blank = True
            elif not sdl[i].isspace():
                line_blank = False
            i += 1
            continue
        if not line_blank:
            out.append(sdl[i:end])
        i = end
    return "".join(out)


def _sdl_definitions(sdl: str) -> dict[tuple[str, str], str] | None:
    """(kind, name) -> text of every top-level definition (an `extend` form
    is its own kind); None when text outside a definition is left after
    removing comments and descriptions."""
    sdl = _sdl_strip(sdl)
    found = list(SDL_DEFINITION.finditer(sdl))
    if sdl[: found[0].start() if found else len(sdl)].strip():
        return None
    out: dict[tuple[str, str], str] = {}
    for i, m in enumerate(found):
        end = found[i + 1].start() if i + 1 < len(found) else len(sdl)
        key = (("extend " if m.group(1) else "") + m.group(2), m.group(3))
        out[key] = out.get(key, "") + sdl[m.start():end]
    return out


def _normal(text: str) -> str:
    return " ".join(text.split())


def _sdl_header(definition: str) -> str:
    """A definition up to its body: name, `implements`, directives."""
    return _normal(definition.split("{", 1)[0])


def _sdl_members(definition: str) -> dict[str, str] | None:
    """Field (or value) name -> normalised text of a definition's body, one
    member per line as the schema is written (arguments may span lines);
    None when a line cannot be assigned to one member."""
    open_at, close_at = definition.find("{"), definition.rfind("}")
    if open_at < 0 or close_at < open_at:
        return None
    members: dict[str, str] = {}
    current, depth = None, 0
    for line in definition[open_at + 1 : close_at].splitlines():
        if not line.strip():
            continue
        if depth == 0:
            m = SDL_MEMBER.match(line)
            if not m:
                return None
            # A repeated member (the schema has had one) shares the entry.
            current = m.group(1)
            members.setdefault(current, "")
        members[current] += " " + " ".join(line.split())
        depth += line.count("(") - line.count(")")
        if depth < 0:
            return None
    return members


@dataclass(frozen=True)
class SchemaChange:
    kind: str  # type / interface / input / enum / scalar / union (no `extend`)
    name: str
    # Changed members of an object type or interface; None: the whole type.
    fields: frozenset[str] | None = None


INPUT_KINDS = ("input", "enum", "scalar")


def _schema_changes(before: str | None, after: str | None) -> list[SchemaChange] | None:
    """What a schema.graphql change touches, definition by definition; None
    when some of it belongs to no named type (see the module docstring).

    An object type or interface changes by field, unless it is added,
    removed, or its header (`implements`, directives) changed: then it
    changes as a whole. A changed input, enum or scalar also changes every
    input whose fields use it, transitively: their generated classes nest
    its serializer."""
    if before is None or after is None:
        return None
    old, new = _sdl_definitions(before), _sdl_definitions(after)
    if old is None or new is None:
        return None
    changes: dict[tuple[str, str], SchemaChange] = {}
    for key in sorted(old.keys() | new.keys()):
        a, b = old.get(key), new.get(key)
        if a is not None and b is not None and _normal(a) == _normal(b):
            continue
        kind, name = key[0].removeprefix("extend "), key[1]
        if kind in ("schema", "directive") or not name:
            return None
        fields = None
        if kind in ("type", "interface") and a is not None and b is not None:
            ma, mb = _sdl_members(a), _sdl_members(b)
            if ma is not None and mb is not None and _sdl_header(a) == _sdl_header(b):
                fields = frozenset(f for f in ma.keys() | mb.keys() if ma.get(f) != mb.get(f))
        changes[(kind, name)] = SchemaChange(kind, name, fields)
    # Inputs that nest a changed input / enum / scalar, transitively.
    nesting: dict[str, set[str]] = collections.defaultdict(set)
    for defs in (old, new):
        for (kind, name), text in defs.items():
            if kind.removeprefix("extend ") == "input":
                for used in set(IDENTIFIER.findall(text.split("{", 1)[-1])):
                    nesting[used].add(name)
    stack = [c.name for c in changes.values() if c.kind in INPUT_KINDS]
    while stack:
        for outer in nesting.get(stack.pop(), ()):
            if ("input", outer) not in changes:
                changes[("input", outer)] = SchemaChange("input", outer)
                stack.append(outer)
    return list(changes.values())


def _type_overrides(graph: Graph, pkg: str) -> dict[str, str]:
    """GraphQL type -> Dart type of the Ferry `type_overrides` in the
    package's build.yaml (an overridden input or scalar has no `G` class:
    `input v2_Upload` is `TenturaV2Upload` in the .var files)."""
    try:
        text = (graph.root / pkg / "build.yaml").read_text(encoding="utf-8")
    except OSError:
        return {}
    out: dict[str, str] = {}
    block_indent = None
    current = None
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        if line.strip() == "type_overrides:":
            block_indent, current = indent, None
            continue
        if block_indent is None:
            continue
        if indent <= block_indent:
            block_indent = None
            continue
        key, _, value = line.strip().partition(":")
        if not value.strip():
            current = key.strip()
        elif current and key.strip() == "name":
            out[current] = value.strip().strip("'\"")
    return out


@dataclass(frozen=True)
class FerryGroup:
    """All Ferry files generated from one document (.ast / .data / .var /
    .req and their .g.dart parts)."""
    files: frozenset[str]
    strings: frozenset[str]
    identifiers: frozenset[str]
    # Types the .ast file references (NamedTypeNode).
    type_names: frozenset[str]


def _ferry_groups(graph: Graph, pkg: str) -> list[FerryGroup]:
    groups: dict[str, set[str]] = collections.defaultdict(set)
    for f in graph.package_files(pkg):
        m = FERRY_FILE.search(f)
        if m and not _ferry_hub(f):
            groups[f[: m.start()] + "/_g/" + m.group(1)].add(f)
    return [
        FerryGroup(
            frozenset(files),
            frozenset().union(*(graph.strings(f) for f in files)),
            # An .ast file is Dart syntax around the document: only its
            # NameNode values name anything (`name:` is an argument there).
            frozenset().union(*(
                NAME_NODE.findall(graph.text(f)) if ".ast.gql" in f else graph.identifiers(f)
                for f in files
            )),
            frozenset().union(*(
                NAMED_TYPE.findall(graph.text(f)) for f in files if ".ast.gql" in f
            )),
        )
        for files in groups.values()
    ]


def _schema_seeds(graph: Graph, pkg: str, changes: list[SchemaChange]) -> set[str]:
    """Dart files of [pkg] that use something [changes] touched, in the forms
    Ferry generates (checked against packages/client/lib/**/_g/):

      * input / enum / scalar N -> class `GN` (inputs also `GNBuilder`) in
        schema.schema.gql.dart, used as `_i4.GN` by the .var / .data files
        of an operation whose variables or results have that type; a
        variable's type is also `NamedTypeNode(name: NameNode(value: 'N'))`
        in its .ast file (a bare NameNode there is a field or argument name:
        `order_by:` is an argument, `order_by` an enum).
        With a build.yaml type_override there is no `GN`: the files use the
        override's Dart type (`TenturaV2Upload` for `v2_Upload`, `DateTime`
        for `timestamptz`, ...). An input or enum used only inline in a
        document (Hasura `where: {...}`, `order_by: {...}`) is in no
        generated file but the hubs: the .ast file is built from the
        document alone (it names fields and enum values, never the input
        type) and no .var file has a variable of that type. So no Dart test
        can observe such a change except the ones reading schema.graphql,
        which always run;
      * object type / interface T -> no class of its own: each selection on
        T is a data class named after the operation whose builder sets
        `G__typename = 'T'`; a selected field F is its getter, or an alias
        of it (`pending: invitation(...)` -> getter `pending`) while the
        .ast file keeps `NameNode(value: 'invitation')` but not 'T'. So an
        operation group matches when one of its files has the string 'T'
        and one of them names F; a whole-type change (added, removed,
        header changed) matches on 'T' alone. An added field is selected by
        no existing document: one that starts using it changes in the same
        commit and is followed by its own rule;
      * union U -> `'U'` (its data classes, fragment type conditions);
      * _g/schema.ast.gql.dart (the AST of the whole schema) changes with any
        definition, so it is always seeded (nothing imports it today).
    A matching group is seeded as a whole. Hand-written files match the same
    way on their own text (`'T'` with F in fixtures, `GN` / `GNBuilder`)."""
    overrides = _type_overrides(graph, pkg)

    def hit(
        strings: frozenset[str], ids: frozenset[str], type_names: frozenset[str] | None
    ) -> bool:
        for c in changes:
            if c.kind in INPUT_KINDS:
                if f"G{c.name}" in ids or f"G{c.name}Builder" in ids:
                    return True
                if type_names is not None and (
                    c.name in type_names or overrides.get(c.name) in ids
                ):
                    return True
            elif c.kind == "union" or c.fields is None:
                if c.name in strings:
                    return True
            elif c.name in strings and not c.fields.isdisjoint(ids):
                return True
        return False

    seeds = set()
    for group in _ferry_groups(graph, pkg):
        if hit(group.strings, group.identifiers, group.type_names):
            seeds |= group.files
    for f in graph.package_files(pkg):
        if "/_g/" not in f and hit(graph.strings(f), graph.identifiers(f), None):
            seeds.add(f)
    # The AST of the whole schema is regenerated by any change to it.
    seeds |= {f for f in graph.package_files(pkg) if f.endswith("/_g/schema.ast.gql.dart")}
    return seeds


def _generated_gql(graph: Graph, pkg: str) -> set[str]:
    return {
        f for f in graph.package_files(pkg)
        if f.startswith(f"{pkg}/lib/") and "/_g/" in f and f.endswith(".gql.dart")
    }


def _naming(graph: Graph, pkg: str, name: str) -> set[str]:
    """Dart files of [pkg] whose code names the basename [name] (a line that
    is only a `//` or `///` comment does not read anything)."""
    return {
        f for f in graph.package_files(pkg)
        if name in graph.text(f) and name in graph.code(f)
    }


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
    sources_changed: set[str] = set()
    schema_changed = False
    schema_seeds: set[str] = set()

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
                continue
            sources_changed.add(rel)
            if rel == "test/flutter_test_config.dart":
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
        if rel.startswith("lib/"):
            sources_changed.add(rel)

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
        elif rel.startswith("lib/") and name == "schema.graphql":
            seeds |= _naming(graph, pkg, name)
            changes = _schema_changes(before(path), after(path))
            if not _generated_gql(graph, pkg):
                whole(f"{rel} (GraphQL schema, no generated Ferry files)")
            elif changes is not None:
                schema_seeds |= _schema_seeds(graph, pkg, changes)
            else:
                schema_changed = True
        elif rel.startswith("lib/") and rel.endswith(".graphql"):
            seeds |= _naming(graph, pkg, name)
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
        elif rel.startswith(("lib/", "integration_test/", "assets/", "fonts/", "images/")):
            whole(rel)
        else:
            # web/, android/, README, ...: what names the file reads it.
            naming = _naming(graph, pkg, name)
            seeds |= naming
            if not naming and rel.startswith("web/"):
                whole(f"{rel} (web file named by no Dart file)")

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
    if sources_changed:
        seeds |= graph.readers_of(pkg, sources_changed)
    if schema_changed:
        seeds |= _generated_gql(graph, pkg)
    reached = graph.reach(seeds)
    reached |= graph.reach(gql_seeds | schema_seeds, skip=_ferry_hub)
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
    if base.startswith("web/"):
        return "unnamed web/ file"
    if base.startswith(("lib/", "assets/", "integration_test/", "fonts/", "images/")):
        if base.endswith("schema.graphql"):
            return "GraphQL schema"
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

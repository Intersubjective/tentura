#!/usr/bin/env python3
"""Check client/server isolation without requiring either package's codegen.

Server tests may use client constants whose file has no package imports or
part directives. Run from anywhere: python3 scripts/check_cross_package_imports.py
"""

from __future__ import annotations

from pathlib import Path
import re
import sys

REPO_ROOT = Path(__file__).resolve().parent.parent
SCOPES = {"client": ("lib", "test", "integration_test"), "server": ("lib", "test")}
# Tokenize strings atomically so Dart source embedded in tests is not scanned
# as code. Comments are tokens too, preserving diagnostic line numbers.
TOKENS = re.compile(
    r"//[^\n]*|/\*.*?\*/|"
    r"r?(?:\"\"\".*?\"\"\"|'''.*?'''|"
    r"'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\")"
    r"|[A-Za-z_][A-Za-z_0-9]*|[^\s]",
    re.DOTALL,
)


def directives(path: Path):
    source = path.read_text(encoding="utf-8")
    tokens = [m for m in TOKENS.finditer(source) if not m.group().startswith(("//", "/*"))]
    index = 0
    while index < len(tokens):
        token = tokens[index]
        kind = token.group()
        index += 1
        if kind not in ("import", "export", "part"):
            continue
        line = source.count("\n", 0, token.start()) + 1
        uris = []
        while index < len(tokens) and tokens[index].group() != ";":
            value = tokens[index].group().removeprefix("r")
            if value.startswith(("'", '"')):
                uris.append(value[1:-1])
            index += 1
        yield kind, line, uris


def target_path(source: Path, uri: str) -> Path | None:
    if uri.startswith("package:"):
        package, _, suffix = uri[len("package:"):].partition("/")
        names = {"tentura": "client", "tentura_server": "server"}
        if package in names:
            return (REPO_ROOT / "packages" / names[package] / "lib" / suffix).resolve()
        return None
    if ":" in uri:
        return None
    return (source.parent / uri).resolve()


def is_pure_client_file(path: Path) -> bool:
    return path.is_file() and all(
        kind != "part" and not any(uri.startswith("package:") for uri in uris)
        for kind, _, uris in directives(path)
    )


def main() -> int:
    checked = 0
    violations = []
    for package, scopes in SCOPES.items():
        other = "server" if package == "client" else "client"
        other_root = REPO_ROOT / "packages" / other
        for scope in scopes:
            for path in sorted((REPO_ROOT / "packages" / package / scope).rglob("*.dart")):
                checked += 1
                for _, line, uris in directives(path):
                    for uri in uris:
                        target = target_path(path, uri)
                        if target is None or not target.is_relative_to(other_root):
                            continue
                        if package == "server" and scope == "test" and is_pure_client_file(target):
                            continue
                        violations.append(
                            f"{path.relative_to(REPO_ROOT)}:{line}: forbidden {other} dependency "
                            f"{target.relative_to(REPO_ROOT)}"
                        )
    print(f"check_cross_package_imports: checked {checked} Dart files in client/lib,test,integration_test and server/lib,test")
    for violation in violations:
        print(violation, file=sys.stderr)
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())

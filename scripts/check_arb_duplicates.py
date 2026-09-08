#!/usr/bin/env python3
"""Reject duplicate JSON keys in ARBs, including nested metadata objects."""

import json
from pathlib import Path
import sys


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate key: {key!r}")
        result[key] = value
    return result


def check(paths):
    errors = []
    for path in paths:
        try:
            json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
        except (ValueError, OSError) as error:
            errors.append(f"{path}: {error}")
    return errors


def main():
    root = Path(__file__).resolve().parents[1] / "packages/client/l10n"
    paths = sorted(root.rglob("*.arb"))
    if not paths:
        sys.exit(f"No ARB files found under {root}")
    errors = check(paths)
    if errors:
        sys.exit("\n".join(errors))
    print(f"ARB duplicate-key check passed ({len(paths)} files).")


if __name__ == "__main__":
    main()

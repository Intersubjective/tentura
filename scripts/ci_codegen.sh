#!/usr/bin/env bash
# Generates code for one workspace package in CI, incrementally.
#
#   bash scripts/ci_codegen.sh <client|server>
#
# Runs inside the builder container from the repository root, after the
# workflow restored the package's codegen cache (`.dart_tool/build` plus
# OUTPUTS_TAR below). Resolves dependencies (and, for the client, runs
# gen-l10n), unpacks the cached generated files, runs build_runner and prints
# how many generated files the source tree holds and a digest of their
# contents. With CODEGEN_SAVE=true it then packs those files into OUTPUTS_TAR
# for the workflow's cache save.
#
# Why the generated files are cached, not just `.dart_tool/build`: they live
# in the source tree (gitignored), next to their inputs. A fresh checkout has
# none, so an asset graph restored on its own finds every in-tree output
# missing and rebuilds all of them, re-analysing the libraries they come from
# (client: 1886 outputs, 65 s locally even on the exact same commit; CI wrote
# 7185 outputs in 163 s). With the files restored as well, an unchanged tree
# writes 0 outputs.
#
# Which files: whatever gitignored files appear in the package during the
# build_runner run — the ignored files present after unpacking and
# build_runner, minus those already there before unpacking (pub get and
# gen-l10n artifacts, which are regenerated on every run anyway). No glob, so a
# new generator's outputs are picked up without touching this script.
#
# Correctness: build_runner compares input digests, so outputs of changed
# inputs are rebuilt; outputs of deleted inputs, and every output of a
# previous build it cannot build on incrementally (changed builders or
# options), are deleted by build_runner itself, which knows them from the
# restored asset graph. That needs a graph this build_runner can read: the
# workflow's restore keys only fall back to entries built from the same
# pubspec.lock. The archive is only unpacked next to that graph — they are
# saved together — never over a file the checkout already has, and not at all
# when one of its paths is now a tracked file.
#
# The digest makes a warm build comparable with a cold one: the same commit
# must print the same digest either way.
set -euo pipefail

pkg=${1:?usage: ci_codegen.sh <client|server>}
pkg_dir="packages/$pkg"
outputs_tar="$pkg_dir/.dart_tool/ci-codegen-outputs.tar"
graph="$pkg_dir/.dart_tool/build/asset_graph.json"

git config --global --add safe.directory '*'

if [ "$pkg" = client ]; then
  flutter pub get
  (cd "$pkg_dir" && flutter gen-l10n)
else
  dart pub get
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Gitignored files of the package, .dart_tool (the cache itself) aside.
# Paths are NUL-separated throughout: git would C-quote unusual names.
list_generated() {
  git ls-files -z --others --ignored --exclude-standard -- "$pkg_dir" \
    ":(exclude)$pkg_dir/.dart_tool" | LC_ALL=C sort -z
}
count() { tr -cd '\0' < "$1" | wc -c; }

# Run on a fresh checkout (as in CI): whatever is gitignored now came from
# pub get / gen-l10n, not from an earlier build_runner run.
list_generated > "$work/before"

# A cached output that is now a tracked file: the restored graph still thinks
# it owns that path and could overwrite or delete it. Build cold instead.
if [ -f "$outputs_tar" ]; then
  python3 -c '
import os, sys, tarfile
with tarfile.open(sys.argv[1]) as t:
    for m in t:
        sys.stdout.buffer.write(os.fsencode(m.name) + b"\0")
' "$outputs_tar" | LC_ALL=C sort -z > "$work/cached"
  git ls-files -z -- "$pkg_dir" | LC_ALL=C sort -z > "$work/tracked"
  LC_ALL=C comm -z -12 "$work/cached" "$work/tracked" > "$work/collisions"
  if [ -s "$work/collisions" ]; then
    echo "Cached generated files collide with tracked files: discarding the cache."
    tr '\0' '\n' < "$work/collisions" | sed -n 1,20p
    rm -rf "$pkg_dir/.dart_tool/build" "$outputs_tar"
  fi
fi

if [ -f "$outputs_tar" ] && [ -f "$graph" ]; then
  # --skip-old-files: a pub get / gen-l10n artifact at the same path wins over
  # the cached copy.
  tar -xf "$outputs_tar" --skip-old-files
  echo "Restored $(count "$work/cached") cached generated files."
elif [ -f "$outputs_tar" ]; then
  echo "Cached generated files without an asset graph: not restoring them."
else
  echo "No cached generated files: full build."
fi

(cd "$pkg_dir" && dart run build_runner build -d)

list_generated > "$work/after"
LC_ALL=C comm -z -13 "$work/before" "$work/after" > "$work/outputs"
digest=$(xargs -0 -r sha256sum < "$work/outputs" | sha256sum | cut -c1-16)
echo "Generated files in $pkg_dir: $(count "$work/outputs"), content digest $digest"

if [ "${CODEGEN_SAVE:-false}" = true ]; then
  if [ ! -s "$work/outputs" ]; then
    # Not a fresh checkout (outputs predate this run) or a broken build:
    # an empty archive would only make the next run rebuild everything.
    echo "No generated files found: not packing a cache archive." >&2
    rm -f "$outputs_tar"
  else
    tar -cf "$outputs_tar" --null -T "$work/outputs"
    echo "Packed them into $outputs_tar for the cache."
  fi
fi

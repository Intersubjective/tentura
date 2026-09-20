#!/usr/bin/env bash
# Flag legacy product/implementation terms in docs/ and structural drift in
# agent rules + root entry-point docs (post-cleanup drift guard).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Every check below is `rg ... 2>/dev/null` inside a condition, so a missing
# binary reads as "no matches" and the whole gate passes without testing
# anything. It did exactly that in CI until ripgrep was added to the builder
# image. Refuse to run rather than report a clean tree we never inspected.
if ! command -v rg >/dev/null 2>&1; then
  echo "check-doc-drift: ripgrep (rg) is required and not installed" >&2
  exit 2
fi

# A line carrying this marker is exempt. Used where a document has to name a
# retired term in order to correct it.
ALLOW_MARKER='drift-ok'

# Legacy product / implementation terms that should no longer appear in docs/.
DOC_PATTERNS=(
  'Registry tab'
  'Overview tab'
  'coordination_status column'
  'beacon\.state'
  'ChatNews'
  'beacon_blocker'
)

# Structural drift in agent rules + root entry-point docs:
#  - applyWhen / pathMatches: inert (unsupported) Cursor rule frontmatter
#  - quick-reference: deleted rule hub, must not be referenced
#  - widgetbook: no such package in the monorepo
#  - terminology alias must be documented in AGENTS.md / CONTEXT.md
TERMINOLOGY_MARKERS=(
  'Terminology alias'
  'internally: Beacon'
)
RULE_DOC_FILES=(
  .cursor/rules
  AGENTS.md
  DEV_GUIDELINES.md
  DEVELOPMENT.md
  README.md
  .claude/CLAUDE.md
)
RULE_DOC_PATTERNS=(
  'applyWhen'
  'pathMatches'
  'quick-reference'
  'widgetbook'
)

found=0
mapfile -d '' TRACKED_DOC_FILES < <(
  git ls-files -z -- 'docs/**' ':!docs/README.md'
)
# An empty list means the pathspec or the repo is wrong, not that docs/ is
# clean: the loop below would skip silently and the gate would pass.
if ((${#TRACKED_DOC_FILES[@]} == 0)); then
  echo "check-doc-drift: no tracked files matched docs/** — refusing to pass" >&2
  exit 2
fi

for pat in "${DOC_PATTERNS[@]}"; do
  hits="$(rg -n "$pat" "${TRACKED_DOC_FILES[@]}" | grep -vF "$ALLOW_MARKER" || true)"
  if [[ -n "$hits" ]]; then
    printf '%s\n' "$hits"
    found=1
  fi
done

for pat in "${RULE_DOC_PATTERNS[@]}"; do
  hits="$(rg -n "$pat" "${RULE_DOC_FILES[@]}" | grep -vF "$ALLOW_MARKER" || true)"
  if [[ -n "$hits" ]]; then
    printf '%s\n' "$hits"
    found=1
  fi
done

for pat in "${TERMINOLOGY_MARKERS[@]}"; do
  if ! grep -qF "$pat" AGENTS.md CONTEXT.md 2>/dev/null; then
    echo "check-doc-drift: missing terminology marker '$pat' in AGENTS.md or CONTEXT.md" >&2
    found=1
  fi
done

if [[ ! -f .cursor/rules/terminology.mdc ]]; then
  echo "check-doc-drift: missing .cursor/rules/terminology.mdc" >&2
  found=1
fi

if [[ $found -eq 0 ]]; then
  echo "check-doc-drift: no legacy terms or rule/doc drift found"
  exit 0
fi
echo "check-doc-drift: drift found (review or update the flagged files)" >&2
exit 1

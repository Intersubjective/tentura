#!/usr/bin/env bash
# Flag legacy product/implementation terms in docs/ and structural drift in
# agent rules + root entry-point docs (post-cleanup drift guard).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

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

for pat in "${DOC_PATTERNS[@]}"; do
  if ((${#TRACKED_DOC_FILES[@]} > 0)) && \
    rg -n "$pat" "${TRACKED_DOC_FILES[@]}" 2>/dev/null; then
    found=1
  fi
done

for pat in "${RULE_DOC_PATTERNS[@]}"; do
  if rg -n "$pat" "${RULE_DOC_FILES[@]}" 2>/dev/null; then
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

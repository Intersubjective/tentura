#!/usr/bin/env bash
# Fail when user-facing copy still uses internal product nouns (beacon / room).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

STRICT="${TERMINOLOGY_STRICT:-1}"
found=0

warn_or_fail() {
  echo "check-user-facing-terminology: $*" >&2
  found=1
}

# ARB values only (skip @metadata keys)
check_arb() {
  local f="$1"
  local lang="$2"
  python3 - "$f" "$lang" <<'PY'
import json, re, sys
path, lang = sys.argv[1], sys.argv[2]
data = json.load(open(path, encoding="utf-8"))
beacon_re = re.compile(r"\b[Bb]eacon\b|\bbeacons\b|\bBeacons\b")
room_re = re.compile(r"\b[Rr]oom\b|\broom\b")
ru_beacon = re.compile(r"маяк", re.I)
ru_room = re.compile(r"комнат", re.I)
hits = []
for k, v in data.items():
    if k.startswith("@") or not isinstance(v, str):
        continue
    if lang == "en":
        if beacon_re.search(v) or room_re.search(v):
            hits.append(f"{path}: {k}: {v[:80]!r}")
    else:
        if ru_beacon.search(v) or ru_room.search(v):
            hits.append(f"{path}: {k}: {v[:80]!r}")
print("\n".join(hits))
PY
}

for f in packages/client/l10n/app_en.arb packages/client/l10n/app_ru.arb; do
  lang=en
  [[ "$f" == *app_ru* ]] && lang=ru
  out=$(check_arb "$f" "$lang" || true)
  if [[ -n "${out:-}" ]]; then
    echo "$out"
    warn_or_fail "ARB values contain banned terms in $f"
  fi
done

# Hardcoded user copy in message classes only
if rg -n "String get toEn => '[^']*\b[Bb]eacon\b|String get toEn =>\s*\n\s*'[^']*\b[Bb]eacon\b" \
  packages/client/lib/features packages/client/lib/ui \
  --glob '**/message/*.dart' 2>/dev/null; then
  warn_or_fail "hardcoded beacon strings in message classes"
fi

if rg -n "Exception\('[^']*\b[Bb]eacon\b" \
  packages/client/lib/features packages/client/lib/ui \
  --glob '**/*_cubit.dart' 2>/dev/null; then
  warn_or_fail "cubit Exception strings still use beacon"
fi

# Server user-visible copy paths
SERVER_COPY=(
  packages/server/lib/domain/notification/beacon_notification_copy_builder.dart
  packages/server/lib/domain/notification/beacon_notification_batch_aggregator.dart
  packages/server/lib/domain/coordination/filter_beacon_notifications.dart
  packages/server/lib/domain/use_case/evaluation/evaluation_participant_graph_builder.dart
)
for f in "${SERVER_COPY[@]}"; do
  if rg -n "'[^']*\b[Bb]eacon\b[^']*'|\"[^\"]*\b[Bb]eacon\b[^\"]*\"" "$f" 2>/dev/null; then
    warn_or_fail "server copy still uses beacon in $f"
  fi
done

# Landing user-facing quoted strings (exclude CSS class names)
if rg -n "(title|body):\s*'[^']*\b[Bb]eacon\b|'\s*\+\s*\"[^\"]*\b[Bb]eacon\b|'a beacon'" \
  packages/landing/onboarding.js 2>/dev/null; then
  warn_or_fail "landing onboarding still uses beacon"
fi
if rg -n "\|\|\s*'a beacon'" packages/landing/main.js 2>/dev/null; then
  warn_or_fail "landing main.js fallback still uses beacon"
fi

# Entry points must document the alias (grep — available in CI builder image)
for f in AGENTS.md CONTEXT.md; do
  if ! grep -qE 'Terminology alias|Request \(internally: Beacon\)|internally: Beacon' "$f" 2>/dev/null; then
    warn_or_fail "$f missing terminology alias documentation"
  fi
done

if [[ $found -eq 0 ]]; then
  echo "check-user-facing-terminology: ok"
  exit 0
fi

if [[ "$STRICT" == "0" ]]; then
  echo "check-user-facing-terminology: WARN mode (TERMINOLOGY_STRICT=0)" >&2
  exit 0
fi
exit 1

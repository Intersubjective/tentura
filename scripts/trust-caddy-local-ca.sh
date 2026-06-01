#!/usr/bin/env bash
# Trust Caddy's `tls internal` root for local HTTPS (Caddyfile.local :9443).
#
# `caddy trust` updates ~/.pki/nssdb (Chrome, curl) but NOT Firefox snap's isolated
# profile — this script covers both.
set -euo pipefail

ROOT="${HOME}/.local/share/caddy/pki/authorities/local/root.crt"
if [[ ! -f "$ROOT" ]]; then
  echo "Missing $ROOT — start Caddy once with Caddyfile.local (tls internal) first." >&2
  exit 1
fi

echo "Running caddy trust (Chrome / system NSS)..."
caddy trust || true

if [[ -d "${HOME}/.pki/nssdb" ]]; then
  certutil -d "sql:${HOME}/.pki/nssdb" \
    -A -t "C,C,C" -n "Caddy Local Authority (local dev)" -i "$ROOT" 2>/dev/null || true
fi

# Firefox snap (Ubuntu): separate cert DB under ~/snap/firefox/...
for profile in "${HOME}/snap/firefox/common/.mozilla/firefox/"*.default*; do
  [[ -d "$profile" ]] || continue
  echo "Importing into Firefox snap profile: $profile"
  certutil -d "sql:${profile}" \
    -A -t "C,C,C" -n "Caddy Local Authority - 2025 ECC Root" -i "$ROOT"
done

# Firefox flatpak
for profile in "${HOME}/.var/app/org.mozilla.firefox/.mozilla/firefox/"*.default*; do
  [[ -d "$profile" ]] || continue
  echo "Importing into Firefox flatpak profile: $profile"
  certutil -d "sql:${profile}" \
    -A -t "C,C,C" -n "Caddy Local Authority - 2025 ECC Root" -i "$ROOT"
done

echo "Done. Restart Firefox completely, then open https://dev.lvh.me:9443/"

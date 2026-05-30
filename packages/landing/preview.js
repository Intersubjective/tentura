// Talks to the Dart server preview endpoint added in Phase 0:
//   GET /api/v2/invite/:code/preview  (guarded by extractJwtClaims, non-failing)
// Response shape (see invite_preview_result.dart):
//   { inviter:{id,displayName,image}, codeStatus, callerStatus, beacon?, suggestedAction }
const API_BASE = (window.TENTURA || {}).apiBase || ''; // '' = same origin

/// Invite URLs: `/invite/:code` on the landing host.
export function parseInviteCode() {
  const m = location.pathname.match(/^\/invite\/([^/]+)/);
  return m ? decodeURIComponent(m[1]) : '';
}

export async function fetchPreview(code) {
  const res = await fetch(
    `${API_BASE}/api/v2/invite/${encodeURIComponent(code)}/preview`,
    {
      headers: { Accept: 'application/json' },
      // Send the session cookie/JWT when present so callerStatus is accurate.
      credentials: 'include',
    },
  );
  if (!res.ok) throw new Error(`preview request failed: ${res.status}`);
  return res.json();
}

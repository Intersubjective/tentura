// Talks to the Dart server preview endpoint on the app host (cross-origin cookie):
//   GET ${appBase}/api/v2/invite/:code/preview  (extractJwtOrSessionClaims)
// Response shape (see invite_preview_result.dart):
//   { inviter:{id,displayName,image}, codeStatus, callerStatus, beacon?, suggestedAction }
const APP_BASE = ((window.TENTURA || {}).appBase || '').replace(/\/$/, '');

/// Invite URLs: `/invite/:code` on the landing host.
export function parseInviteCode() {
  const m = location.pathname.match(/^\/invite\/([^/]+)/);
  return m ? decodeURIComponent(m[1]) : '';
}

export async function fetchPreview(code) {
  if (!APP_BASE) {
    throw new Error('appBase is not configured');
  }
  const res = await fetch(
    `${APP_BASE}/api/v2/invite/${encodeURIComponent(code)}/preview`,
    {
      headers: { Accept: 'application/json' },
      credentials: 'include',
    },
  );
  if (!res.ok) throw new Error(`preview request failed: ${res.status}`);
  return res.json();
}

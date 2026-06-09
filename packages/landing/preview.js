// Talks to the Dart server preview endpoint on the same origin:
//   GET /api/v2/invite/:code/preview  (extractJwtOrSessionClaims)
// Response shape (see invite_preview_result.dart):
//   { inviter:{id,displayName,image}, codeStatus, callerStatus, beacon?, suggestedAction }

/// Invite URLs: `/invite/:code` on the landing host.
export function parseInviteCode() {
  const m = location.pathname.match(/^\/invite\/([^/]+)/);
  return m ? decodeURIComponent(m[1]) : '';
}

export async function fetchPreview(code) {
  const res = await fetch(
    `/api/v2/invite/${encodeURIComponent(code)}/preview`,
    {
      headers: { Accept: 'application/json' },
      credentials: 'include',
    },
  );
  if (!res.ok) throw new Error(`preview request failed: ${res.status}`);
  return res.json();
}

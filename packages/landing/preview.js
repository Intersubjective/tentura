// Talks to the Dart server preview endpoint on the same origin:
//   GET /api/v2/invite/:code/preview  (extractJwtOrSessionClaims)
// Response shape (see invite_preview_result.dart):
//   { inviter:{id,displayName,image}, codeStatus, callerStatus, beacon?, suggestedAction }

import { normalizeInviteCode } from './invite_entry.js';

/// Invite URLs: `/invite/:code` on the landing host.
export function parseInviteCode() {
  const m = location.pathname.match(/^\/invite\/([^/]+)/);
  if (!m) return '';
  try {
    return normalizeInviteCode(decodeURIComponent(m[1]));
  } catch {
    return '';
  }
}

/** Raw path segment before normalization (for trailing-dash hints). */
export function parseInviteCodeRaw() {
  const m = location.pathname.match(/^\/invite\/([^/]+)/);
  if (!m) return '';
  try {
    return decodeURIComponent(m[1]).trim();
  } catch {
    return '';
  }
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

/** Strip whitespace and trailing `-` from pasted/URL invite fragments. */
export function normalizeInviteCode(raw) {
  let code = (raw || '').trim();
  while (code.endsWith('-')) {
    code = code.slice(0, -1);
  }
  return code;
}

/** Anchored invite code (client kInvitationCodeRegExp: I[a-f0-9]{0,12}). */
export const INVITE_CODE_PATTERN = /^I[a-f0-9]{1,12}$/;

const INVITE_PATH_RE = /\/invite\/([^/?#]+)/;

/** True when [raw] ends with `-` after trim (common paste typo). */
export function inviteCodeHadTrailingDash(raw) {
  return (raw || '').trim().endsWith('-');
}

/**
 * Parse pasted invite link or raw code. Never returns an external origin.
 * @returns {{ ok: true, code: string } | { ok: false, error: string }}
 */
export function parseInviteEntryInput(raw) {
  const trimmed = (raw || '').trim();
  if (!trimmed) {
    return { ok: false, error: 'Enter an invite link or code.' };
  }

  const pathMatch = trimmed.match(INVITE_PATH_RE);
  let candidate = pathMatch ? pathMatch[1] : trimmed;

  try {
    candidate = decodeURIComponent(candidate);
  } catch {
    return { ok: false, error: 'That invite link does not look valid.' };
  }

  candidate = normalizeInviteCode(candidate.split(/[?#]/)[0]);
  if (!INVITE_CODE_PATTERN.test(candidate)) {
    return {
      ok: false,
      error: 'Enter a valid invite link or code (starts with I).',
    };
  }

  return { ok: true, code: candidate };
}

/** Same-origin path for a validated invite code. */
export function invitePathForCode(code) {
  return `/invite/${encodeURIComponent(code)}`;
}

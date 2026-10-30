// Email magic-link auth for the static landing (Tier 1 + Tier 2).
// New web accounts are created via email OTP or Google OAuth — not device-seed signup.

import { t } from './onboarding.js';

const API_BASE = (window.TENTURA || {}).apiBase || ''; // '' = same origin

export class EmailLinkError extends Error {
  /**
   * @param {string} message shown inline to the user
   * @param {{userInput?: boolean}} [opts] userInput: the address the user typed
   *   was rejected (empty or malformed). Expected input, not a fault, so
   *   analytics keeps it as a breadcrumb and does not open a Sentry issue.
   *   expected: another expected answer shown to the user (a 4xx from the
   *   server, e.g. a refused test-login domain); also no Sentry issue (#788).
   *   userInput implies expected.
   */
  constructor(message, { userInput = false, expected = false } = {}) {
    super(message);
    this.name = 'EmailLinkError';
    this.userInput = userInput;
    this.expected = userInput || expected;
  }
}

// Same rule as the server's kAuthEmailPattern (email_auth_util.dart). The
// server answers {ok:true} even for a malformed address (it never reveals
// whether a link went out), so the page would claim "Link sent" for "nope".
export const EMAIL_PATTERN = /^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$/;

/** Whether a normalized (trimmed, lower-cased) address can receive a link. */
export function isValidEmailFormat(normalized) {
  return EMAIL_PATTERN.test(normalized);
}

/** Start magic-link sign-in/signup; server always responds generically when accepted. */
export async function startEmailMagicLink({ email, code }) {
  const normalized = (email || '').trim().toLowerCase();
  if (!normalized) throw new EmailLinkError(t('Please enter your email.'), { userInput: true });
  if (!isValidEmailFormat(normalized)) {
    throw new EmailLinkError(t('Please enter a valid email address.'), { userInput: true });
  }
  const payload = { email: normalized };
  if (code) payload.inviteCode = code;
  let res;
  try {
    res = await fetch(`${API_BASE}/api/v2/auth/email/start`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify(payload),
    });
  } catch (e) {
    throw new EmailLinkError(t('Could not reach the server ({error}).', { error: e }));
  }
  if (res.status === 400) {
    // The server is the authority on the format (it checks before any rate
    // limit or account lookup, so this reveals nothing about accounts).
    const data = await res.json().catch(() => null);
    if (data?.error === 'invalid_email') {
      throw new EmailLinkError(t('Please enter a valid email address.'), { userInput: true });
    }
  }
  if (!res.ok) {
    throw new EmailLinkError(t('Something went wrong. Please try again.'));
  }
  const data = await res.json();
  return data?.attemptId ?? null;
}

/** QA immediate sign-in for allowlisted test domains (dev/staging only). */
export async function startTestLogin({ email, code }) {
  const normalized = (email || '').trim().toLowerCase();
  if (!normalized) throw new EmailLinkError(t('Please enter your email.'), { userInput: true });
  const payload = { email: normalized };
  if (code) payload.inviteCode = code;
  let res;
  try {
    res = await fetch(`${API_BASE}/api/v2/auth/email/test-login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify(payload),
    });
  } catch (e) {
    throw new EmailLinkError(t('Could not reach the server ({error}).', { error: e }));
  }
  if (res.status === 409) {
    // The invite on this page is used, expired or unknown (#788, /invite/):
    // an expected answer shown inline, no Sentry issue.
    const data = await res.json().catch(() => null);
    const message =
      {
        invite_used: 'This invite has already been used.',
        invite_expired: 'This invite has expired.',
      }[data?.error] ?? 'This invite link is no longer valid';
    throw new EmailLinkError(t(message), { expected: true });
  }
  if (!res.ok) {
    // A 400 is the server refusing this address (QA domain not allowed or
    // malformed): expected, shown inline, no Sentry issue (#788), the same
    // rule saveDisplayName uses (#762). Anything else stays a fault: 404
    // means QA_SIMPLE_LOGIN_MODE is off on a server whose landing shows the
    // button (config mismatch), 403/429/other 4xx and 5xx likewise.
    throw new EmailLinkError(
      t('Test login failed. Check the email domain and try again.'),
      {
        expected: res.status === 400,
      },
    );
  }
  const data = await res.json();
  return {
    redirectUrl: data?.redirectUrl ?? null,
    isNewAccount: Boolean(data?.isNewAccount),
  };
}

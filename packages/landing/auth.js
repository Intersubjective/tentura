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
   */
  constructor(message, { userInput = false } = {}) {
    super(message);
    this.name = 'EmailLinkError';
    this.userInput = userInput;
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
  if (!res.ok) {
    throw new EmailLinkError('Test login failed. Check the email domain and try again.');
  }
  const data = await res.json();
  return {
    redirectUrl: data?.redirectUrl ?? null,
    isNewAccount: Boolean(data?.isNewAccount),
  };
}

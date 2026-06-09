// Email magic-link auth for the static landing (Tier 1 + Tier 2).
// New web accounts are created via email OTP or Google OAuth — not device-seed signup.

const API_BASE = (window.TENTURA || {}).apiBase || ''; // '' = same origin

export class EmailLinkError extends Error {
  constructor(message) {
    super(message);
    this.name = 'EmailLinkError';
  }
}

/** Start magic-link sign-in/signup; server always responds generically when accepted. */
export async function startEmailMagicLink({ email, code }) {
  const normalized = (email || '').trim().toLowerCase();
  if (!normalized) throw new EmailLinkError('Please enter your email.');
  const body = { email: normalized };
  if (code) body.inviteCode = code;
  let res;
  try {
    res = await fetch(`${API_BASE}/api/v2/auth/email/start`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify(body),
    });
  } catch (e) {
    throw new EmailLinkError(`Could not reach the server (${e}).`);
  }
  if (!res.ok) {
    throw new EmailLinkError('Something went wrong. Please try again.');
  }
}

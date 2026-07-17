---
status: done
kind: audit
---
# Staging QA — Beacon invite & forward flow

End-to-end QA on https://dev.tentura.io exercising friend invite signup, magic-link auth, inbox commit (offer help), beacon forward, forward-beacon invite, second-user signup, and partial beacon creation. Complements the beacon-detail product audit in [`docs/audits/beacon-detail-qa-audit.md`](beacon-detail-qa-audit.md).

**Date:** 2026-06-26  
**Environment:** https://dev.tentura.io  
**Method:** Browser automation via normal UI + `/_qa/latest-email` magic-link retrieval (no Google login, no direct session/DB APIs).

---

## QA accounts (reuse for future login tests)

| Role | Email | Notes |
|------|-------|-------|
| **User A** (friend's invitee) | `agent-3c4703tb@test.tentura.local` | Registered via Vadim's beacon invite; offered help; forwarded beacon |
| **User B** (forward invitee) | `agent-zl3i4kxe@test.tentura.local` | Registered via User A's forward-beacon invite; offered help on same beacon |

---

## Flow summary

| Step | Result |
|------|--------|
| Open friend invite `…/invite/I806d29daebbe-` | **Failed** — "This invite link is no longer valid" |
| Same code **without trailing dash** `I806d29daebbe` | **Worked** — Vadim's beacon "Тентура: AuthN по Oauth" |
| User A magic-link signup + onboarding | **Passed** — landed in app as `agent 3c4703tb` (A3) |
| Beacon in Inbox → Offer Help (commit) | **Passed** — moved to My Work; Inbox cleared |
| Forward screen affordances | **Mostly passed** — see per-screen notes |
| Forward to existing user + shared note | **Partial** — red error snackbar after forward |
| Create forward-beacon invite ("QA User B") | **Passed** — `https://dev.tentura.io/invite/I67ef5c9a5d81` |
| Logout → User B signup via forward invite | **Passed** |
| User B commit to same beacon | **Passed** |
| User B create own beacon | **Incomplete** — form filled; Publish blocked until Requirements saved; requirements sheet Save did not dismiss reliably |

---

## Per-screen UX findings

### 1. Invite-only landing (`/invite/?#`)

- **Legibility:** Good contrast, clear hierarchy.
- **Issues:**
  - Trailing dash in pasted URL (`I806d29daebbe-`) fails client validation with a generic message — easy to misread as "invalid code" when the server would accept it without the dash.
  - "I already have an account" is collapsed by default; returning users may not see email login immediately.

### 2. Invalid invite page (`/invite/I806d29daebbe-`)

- **Issues:**
  - Dead end — no "paste a different code" or link back to `/invite/`.
  - No hint that a trailing `-` might be the problem.

### 3. Friend invite preview (`/invite/I806d29daebbe`)

- **Legibility:** Good; inviter + beacon preview are clear.
- **Issues:**
  - **Language mix:** UI in English, beacon title/description in Russian — confusing for EN-only users.
  - Inviter shown as raw email prefix (`agent 3c4703tb`) rather than a display name after signup.
  - "Email me a sign-in link" gives no in-page "check your email" confirmation (field disables; easy to miss success).

### 4. Magic-link confirm (`/auth/email/verify`)

- **Legibility:** Excellent; scanner-safe copy is clear.
- **Issues:** Button says "Continue to Tentura" here but post-signup landing says "Open Tentura" — minor label inconsistency.

### 5. Post-signup landing ("You're all set")

- **Legibility:** Good.
- **Issues:** Skips name/onboarding — new users jump straight to empty My Work with default initials (A3). No prompt to set display name.

### 6. WASM boot (black screen)

- **Issues:** Several seconds of blank/black screen before UI; "Enable accessibility" may flash. First impression feels broken on slow loads.

### 7. My Work (empty state)

- **Legibility:** Clear empty state copy.
- **Issues:**
  - **Navigation lag:** Sidebar tab highlight and main content can desync (URL `#/home/work` while Inbox content still visible).
  - Filter bar ("Active", "Recent", "+") shown on empty list — low value noise.
  - Vast whitespace on desktop; single card floats at top with no max-width.

### 8. Inbox — Needs me

- **Legibility:** Card actions (Offer Help / Forward) are clear.
- **Issues:**
  - **Dismiss (X) vs card tap:** X opens "Can't help?" — easy to hit by mistake; wording sounds like decline, not dismiss-from-inbox.
  - "needs attention" is small red lowercase — low salience.
  - **Language mix** on beacon card (RU title, EN chrome).
  - "Forwarded by" on User B's card showed **AZ** (self) — likely wrong forwarder attribution.
  - Card body not obviously clickable for beacon detail; only overflow / action buttons discoverable.

### 9. Offer Help modal

- **Legibility:** Category accordion is scannable.
- **Issues:**
  - "How will you help?" is a single underline, not a boxed textarea — looks inactive.
  - "Offer help (0/4)" stays enabled-looking even at 0 selections (should be disabled).
  - Long category list requires much scrolling; search helps but isn't prominent.
  - After submit, snackbar "Help offered! Forward it to someone?" competes with navigation — easy to miss.

### 10. Forward Beacon screen (`#/forward/B1acfdc5d02a6`)

**Affordances tested:** Close, search, `unseen/25` vs `involved/5` tabs, recipient checkboxes, "Why are you forwarding?", personalized note, shared note, invite new person, View invitations, Forward to N.

- **Legibility:** Dense list; avatars + "Last seen" help.
- **Issues:**
  - **Tab labels** `unseen/25` and `involved/5` — slash notation is dev-ish, not user-friendly.
  - **Future dates** in "Last seen" (e.g. Jun 12, 2026) — looks like bad data on staging.
  - **Disabled "Select recipients"** has very low contrast (light gray on white).
  - Selecting a recipient reveals "Why are you forwarding?" / personalized note — good, but not explained until after selection.
  - **Invite modal stacks over QR dialog** — "For whom is this invite?" can obscure the code you just generated.
  - QR uses dot pattern — may reduce scan reliability vs standard QR.
  - **Critical bug:** After "Forward to 1", red snackbar: **`Bad state: Cannot emit new states after calling close`** — raw dev error exposed to user; forward may still have succeeded.
  - Mixed RU/EN in subtitle again.

### 11. Profile

- **Legibility:** Good; Logout is clearly destructive (red).
- **Issues:**
  - Internal user id (`U131e7da0f859`) shown in header — noise for normal users.
  - Logout needs **two clicks** (Logout → confirm) — fine, but first click sometimes didn't open dialog on first attempt.
  - Profile tab can lag 1–2s before content appears after click.

### 12. Logout confirm

- **Legibility:** Good.
- **No major issues.**

### 13. Create Beacon (`#/beacon/new`)

- **Legibility:** Form structure is logical; character counters help.
- **Issues:**
  - **Publish** stays disabled with no inline explanation (Requirements required but not obvious).
  - Requirements bottom sheet: clicking **Technical** expanded **Communication** sub-items first — accordion state bug.
  - **Save** on requirements sheet didn't clearly return to main form (Escape also ineffective).
  - Placeholder contrast on title/description is very light.
  - "Need" vs "What is needed?" — duplicate concept labels.

### 14. Beacon detail

- **Not reached** — inbox card didn't open detail on tap; only overflow menu worked from My Work.

---

## Critical / high-priority bugs

| # | Bug | Severity |
|---|-----|----------|
| 1 | **Invite URL trailing dash** — `I806d29daebbe-` invalid on server; `I806d29daebbe` works. Pasting full URL with trailing `-` fails client validation. | High |
| 2 | **Forward completion error** — `Bad state: Cannot emit new states after calling close` shown to users. | Critical |
| 3 | **Sidebar/content desync** — tab highlight, URL, and visible panel don't always match. | High |
| 4 | **Wrong "Forwarded by"** — User B may see themselves as forwarder. | High |

---

## Recommendations (quick wins)

1. Normalize invite codes (strip trailing `-` on paste).
2. Replace raw error strings with user-safe messages; fix cubit lifecycle on forward.
3. Add post-signup name prompt or profile nudge.
4. Make inbox cards open beacon detail on tap.
5. Rename forward tabs to "Not yet seen (25)" / "Already involved (5)".
6. Disable "Offer help" until ≥1 category selected.
7. Hide internal user IDs from profile header.

---

## Invite links used

| Purpose | URL |
|---------|-----|
| Friend's original (works without `-`) | `https://dev.tentura.io/invite/I806d29daebbe` |
| User A → User B forward invite | `https://dev.tentura.io/invite/I67ef5c9a5d81` |

---

## Overall assessment

Core flows (magic-link auth, invite signup, inbox commit, forward + forward-invite, second-user signup) work on staging. The largest UX gaps are navigation desync, exposed dev errors, invite URL edge cases, language mixing on beacon content, and weak discoverability of beacon detail from inbox cards. Beacon creation needs clearer Publish gating and a more reliable Requirements picker dismiss.

**Incomplete at session end:** User B beacon publish; deep affordance pass on forward screen after second-user flow.

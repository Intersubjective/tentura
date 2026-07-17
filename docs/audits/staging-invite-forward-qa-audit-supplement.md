---
status: historical
kind: audit
---
# Staging QA supplement — findings not in main audit

Delta findings from the **continuation session** (same day as [`docs/audits/staging-invite-forward-qa-audit.md`](staging-invite-forward-qa-audit.md)). Only items **not already covered** in that report are listed here.

**Date:** 2026-06-26  
**Environment:** https://dev.tentura.io  
**Accounts:** `agent-3c4703tb@test.tentura.local` (User A), `agent-zl3i4kxe@test.tentura.local` (User B)

---

## Flows verified (additions)

| Step | Result |
|------|--------|
| **Returning login (User A)** | **Passed** — “I already have an account” on invite-only landing → magic link → existing account opens with prior beacon in My Work |
| **Forward involved tab (User B)** | **Passed** — `involved/7` (was `involved/5` for User A); lists committers with “Help Offered”, including User A (`A3 agent 3c4703tb`) |
| **Forward search** | **Passed** — search icon refocuses list; recipients annotated “Matches this beacon’s stated needs” |

---

## New per-screen issues

### Returning login — invite-only landing (`/invite/?#`)

- Page `<title>` and heading remain **“Tentura is invite-only”** while the expanded **Sign in** block is visible — mixed message for returning users.
- Sign-in expand/collapse works (`I already have an account` ↔ `Have an invite link?`).

### My Work — load failure state

- **Generic error UI:** red `!` icon + **Try again** only — no error text, code, or distinction (network vs permissions vs server).
- **User B:** My Work list **consistently failed** to load (Try again did not recover during session).
- **User A:** Same error appeared intermittently; full reload + returning login restored list with beacon card visible.

### Beacon detail — error state (`#/beacon/view/B1acfdc5d02a6`)

- Direct navigation loads **“Beacon unavailable”** (not merely “not reached via inbox tap”).
- Accessibility heading is **duplicated:** `Beacon unavailable Beacon unavailable`.
- **Try again** on this screen did not recover.
- **Wrong route:** `#/beacon/B1acfdc5d02a6` (missing `/view`) redirected to `#/home/work` instead of correcting or showing a clear 404.
- After hitting unavailable state, **Inbox** briefly showed the same error overlay; **Back** control was not found / did not dismiss overlay — required full app reload (`/`).

### Create Beacon — Requirements picker (worsened behavior)

- **Data loss (new):** Saving requirements closes the bottom sheet and **wipes the parent form** (title, need, done-when cleared) — worse than “sheet didn’t dismiss”.
- **Selection loss:** First **Save** can clear the checked requirement without updating the Requirements row on the parent form.
- Publish remained disabled after refill + requirements attempt; own beacon was **not published**.

### Forward Beacon — search vs tab context

- Activating **search** while on the **involved** tab appeared to **switch context back to unseen** recipient list — disorienting when reviewing already-involved people.

---

## New critical / high-priority bugs

| # | Bug | Severity |
|---|-----|----------|
| 5 | **Requirements Save wipes create-beacon form** — parent fields cleared when requirements sheet closes. | Critical |
| 6 | **My Work load failure** — content area shows context-free Try again; User B could not load list at all. | High |
| 7 | **Beacon view unavailable** — `#/beacon/view/B1acfdc5d02a6` fails for committed participant; error state traps navigation. | High |
| 8 | **Invalid beacon route** — `#/beacon/:id` (no `/view`) silently lands on My Work. | Medium |

---

## Observable state changes (for regression)

- OAuth beacon participant count on User A My Work card: **+6 → +8** after forward/commit activity (suggests forward flow had server-side effect despite client error snackbar).

---

## Still open after supplement

- User B publish own beacon and forward affordances **from author-owned beacon**.
- In-app beacon detail activity (Items / People / Log tabs) — blocked by unavailable route on staging during this session.

---

## Recommendations (supplement only)

1. Preserve create-beacon draft when Requirements sheet opens/closes; never reset parent form on Save.
2. Add actionable copy to My Work / beacon view error states (and log reference for support).
3. Fix or redirect `#/beacon/:id` → `#/beacon/view/:id`.
4. Keep forward search scoped to the active tab (unseen vs involved).
5. Align landing page title/heading with expanded sign-in mode for returning users.

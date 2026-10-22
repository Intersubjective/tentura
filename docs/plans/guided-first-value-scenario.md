# Guided first-value scenario (#91)

Status: **plan only, rev 1 (2026-10-22)** — decision D7 of the Opus sprint
(`docs/plans/2026-10-22-opus-sprint-decisions.md`). No code until the owner approves it.
Parent: #72. Related: #252 (empty states), #261 (plain trust hints), #523 (inviter-first
screen), #248 (Post = chat), #236 (session research umbrella).

## 1. Problem

Facilitated sessions (#72, #96, #142, #236) needed long verbal explanations. One participant
understood the activity after about 40 minutes; another assumed the people they wanted to ask
had to be direct contacts already on Tentura. The failure that recurs in every session is
comprehension of **trust → visibility → relay**: who can see a Request, why it reached me, and
what forwarding does.

Hypothesis (#91): a newcomer learns the model faster by finishing **one small Request loop**
than by reading about MeritRank or the graph. Explain only the concept the current step needs.

## 2. What already exists (lane 2, this sprint)

- First in-app screen names the inviter and offers "See what <name> needs" (#523); a
  request-scoped invite opens that Request directly (landing → `tentura_post_join_beacon`).
- Recipient picker and Field empty states with one truthful sentence on trust and visibility,
  plus an invite action (#252).
- Picker groups: "Your connections" / "Others you can reach" (#440).
- Plain hover/tap explanations on the Field legend and the profile eye (#261).
- "How Tentura works" sheet (Settings, profile, first-run panel).

The scenario below strings these together; it adds no new noun.

## 3. Scenario

### 3.1 Which Request the newcomer practises on

Never fabricate content from real people. In order of preference:

1. **The invite's Request** — a request-scoped invite already opens it. Use it.
2. **A live Request from the inviter or another direct contact** that the newcomer can read.
3. **A practice Request** authored by a clearly labelled system account ("Tentura guide" /
   «Гид Tentura»), visible only to the newcomer, marked «Практика» / "Practice" everywhere,
   excluded from the Field of everyone else, from MeritRank, from closure/trust settlement and
   from every count. It closes itself when the scenario ends or after 7 days.

Options 1–2 teach on the real network; option 3 exists only so a newcomer with an empty
network is not stuck. Open question Q1 (§7): is the practice account acceptable at all?

### 3.2 Steps (progressive disclosure)

Each step shows one short coach line anchored to the real control, with "Next" and "Skip
tour". No modal walls; nothing is long-press only (touch + desktop, see
`cross-platform-gesture-affordances`).

| # | Step | The one concept taught | Done when |
|---|---|---|---|
| 1 | **Why this reached me.** Open the Request; the coach line points at the "how it reached you" path (forward chain / "How this request spread"). | Requests travel person to person through trust; you see it because someone you are connected to sent it or because you can see its author. | The path is opened once. |
| 2 | **Offer or forward.** Two equal choices: "Offer help" or "Forward" to someone better placed. | Forwarding is a normal, useful answer; the picker shows your connections first. | An offer or a forward is sent (practice: simulated, never delivered to real people). |
| 3 | **See the response.** On a real Request: the author's admission / reply arrives via Updates. On practice: the guide account answers within seconds. | The other side sees what you did; Updates is where answers land. | The response is opened. |
| 4 | **Enter the discussion.** Open the Request's discussion with explicit membership ("you are in because …"). | Membership is explicit; the discussion is private to admitted people. | One message sent, or the discussion opened. |
| 5 | **Close the loop.** Author marks the outcome (practice: the guide closes and shows the private thank-you step). | Requests end; feedback after close is private. | Closure seen. |
| 6 | **What changed.** The Field / People view highlights the person you interacted with and the one sentence: "People you trust, and who trust you back, widen whom you can see and send to." | Trust widens visibility; it is mutual and not a fixed number of hops. | The Field is opened once. |

Skip at any step; replay from Settings → "How Tentura works" → "Try it" and from the first-run
panel. Completion state is per account (same store as `HomeOrientationPreferencesPort`).

### 3.3 Copy rules

- User-facing nouns per `.cursor/rules/terminology.mdc` (Request / discussion; Post / chat).
- Never promise a fixed hop count; visibility is mutual and MeritRank-dependent (D6).
- Never say "MeritRank" to a newcomer; "trust network" / «сеть доверия».
- RU uses formal «вы». Owner proofreads EN/RU before merge.

## 4. Comprehension test protocol

Adapted from the closure release gate (`docs/plans/episode-closure-implementation-plan.md` §8,
"Тест понимания"), same format so results are comparable.

- **Format:** RITE — 2–3 rounds of 8–10 people with fixes between rounds, then a confirming
  round of 20. At least half are newcomers who have never seen Tentura. Mobile first, plus a
  desktop pass (keyboard, hover). First an unassisted pass with no hints, then think-aloud and
  the (i) explanations. Repeat questions 2, 4 and 6 a day later in different words. Report
  absolute numbers and the reasons for errors, not one percentage.
- **Stand:** QA stack with seeded networks (`scripts/seed_society`): (a) newcomer invited with
  a request-scoped invite; (b) newcomer with one connection and no Requests (practice path);
  (c) newcomer whose inviter has two open Requests. Engineering panels hidden.
- **Tasks:** find out why a Request reached you; pass a Request to someone better placed;
  offer help; find the answer to your offer; open the discussion; find the person you helped
  on the Field.
- **Questions with correct answers:**
  1. Why did this Request reach you? (Someone connected to me sent it / I can see its author.)
  2. You post a Request and send it to nobody, with "Let people find this request" off. Who
     sees it? (Nobody yet.) And with it on? (People who can see me may find it on the Field.)
  3. Can you send a Request to someone who is not on Tentura? (Yes, with an invite link.)
  4. You trust Ann but Ann has not trusted you. Can Ann see your Requests? (Not necessarily;
     visibility goes both ways.)
  5. Is forwarding a way of saying no? (No — it passes the Request to someone better placed;
     you can still offer help.)
  6. Who can read the discussion? (Only people admitted to it.)
  7. Who learns what you wrote in the private thank-you after closing? (Only the person you
     wrote it to.)
  8. Describe Tentura in one sentence. (Rubric: asking for and passing on help through
     people you trust.)
- **Pass criteria:** questions 2, 4, 6 ≥ 85% correct with no confident wrong "everyone can see
  it"; questions 1, 3, 5, 7 ≥ 85%; question 8 meets the rubric in ≥ 80% (#91 acceptance:
  "describe Tentura as trusted request relay"); median time to first forward or offer ≤ 3 min
  from the first screen; SEQ ≥ 5/7; skip rate per step reported. Validate once more with an
  unmoderated follow-up test (#91).

## 5. Minimal funnel events

No analytics stack exists today. Prefer facts the server already stores; add one small,
pseudonymous event table only for what cannot be derived.

**Derived (no new instrumentation):** signup time (`user.created_at`), invitation accepted
(`invite_genealogy.created_at`), first forward sent (`beacon_forward_edge`), first offer
(help offer rows), first discussion message, first Request created, first trust edge.

**New `product_event` (append-only, client → V2 mutation, rate-limited):**

| Event | Properties | Why |
|---|---|---|
| `scenario_step_shown` | step 1–6, source (invite / contact / practice) | drop-off by step |
| `scenario_step_done` | step, ms since shown | time per step |
| `scenario_skipped` | step | where people bail |
| `scenario_replayed` | entry point | is replay used |
| `help_opened` | surface (legend row, eye info, rating info, empty state) | which explanations people need |

Rules: user id only (no content, no titles, no recipient ids); 90-day retention; covered by
account erasure; no third-party SDK. Funnel report = derived facts joined with these events,
per cohort week: signup → first screen → step 1 … 6 → first real forward/offer within 7 days.

## 6. Delivery outline (after approval)

1. Server: `product_event` table + V2 mutation + erasure hook; practice-Request support only
   if Q1 is approved (system account, visibility guard, exclusion from MR/closure/counts).
2. Client: coach-line component (design-system tokens, anchored, dismissible, hover + tap);
   scenario state per account; steps wired to existing screens; replay entry points.
3. Copy (EN/RU) + owner proofreading; terminology test extended to coach lines.
4. RITE rounds on the QA stand, then the confirming round; ship behind a flag until the pass
   criteria hold.

## 7. Open questions for the owner

- **Q1** Is a labelled practice Request from a system account acceptable, or should a
  newcomer with an empty network get only the empty states + invite (no practice loop)?
- **Q2** Should the scenario start automatically on first run, or only from the first-run
  panel's action?
- **Q3** Is the `product_event` table acceptable (pseudonymous, no content), or derived facts
  only?
- **Q4** Does step 5 (closure) belong in the first-run loop, or in a second, later tour once
  the newcomer authors a Request?

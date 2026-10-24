# QA backlog batch 2026-10-24 (23 GitHub issues)

Audit of 23 open issues against `main` 0275957bc (2026-10-24): what is already
shipped, what is left, and the Alloy beads cut for what is left. Epic in bd:
label `qa-batch-1024`.

The batch runs as **one block after the Post lifetime epic** (`tentura-lkkq`,
gated on its ship bead `tentura-lkkq.23`), see the "epics in blocks" rule: the
Field beads must land after People tags (`tentura-x56h`, which reworks the
Field detail levels) and the #666 beads after Post lifetime (which reworks
`PostCloseOperation`).

## Owner decisions (2026-10-24)

| # | Decision |
|---|----------|
| #666 | Only the Post author may close a Post when budding. Non-authors don't see «Close the post»; their bud goes through without closing. The server rejects `closePost` from a non-author with a typed error. |
| #545 | Option C of `loading-pattern-proposal-2026-10.md` as written: `TenturaFirstLoadGate` (spinner after 150 ms, render what is there after 2.5 s), a per-cubit `firstLoadDone` latch, rollout Request → Activity → My Work → People. Raw-spinner lint later. |
| #459 | Keep the #595 collision policy. Posts get a label from `rootExcerpt`, a hidden name shows on mouse hover, and below the closest detail level an overflow chip that doesn't fit is not drawn. |
| #672 | A removed tier-1 edge between the viewer and someone on the Field triggers one FULL, at least 10 s apart, so content follows the ring. |
| #520 | The seed link reads «I already have an account» and sits behind the existing-account toggle on the invite page too. |
| #482 | "Closed poll" = the room is read-only: then everyone sees the results. The author sees voters without voting; «N votes» opens the voter list (non-anonymous only). |
| #656 | The Timeline sheet's first-line-of-question is **not** approved (privacy). Only the unread count on the Questions row is done; the rest waits. |

## Audit

Status: DONE = shipped, only owner verification on dev is left.

| Issue | Status | Left | Size |
|---|---|---|---|
| #246 direct contacts on Field | DONE (lane 3, 7.46.0) | owner check | — |
| #359 graph after Stop trusting | DONE (2cd7f4772, 71f56c1e1) | owner check; the #402 spotlight on tap is by design | — |
| #394 block leaves trusted | DONE (c90fae203; one auto-dismiss bar via #495/#470) | owner check | — |
| #396 forward provenance | DONE (7.45.0) | optional: graph marks a withdrawn recipient | — |
| #487 child request nesting | DONE (7.45.0) | owner check | — |
| #516 withdrawal | DONE (7.46.0) | optional: per-role helper confirmation copy | — |
| #655 Questions row | DONE (7.45.0) | owner check; a `canRead=false` answer is never retried | — |
| #674 splash SqliteException | DONE (7.45.0, reopen + boot failure + Reload) | optional: close DB on `pagehide` | — |
| #666 non-author closes Post | NOT STARTED | server guard, notice order, client checkbox | M |
| #654 room follow-ups | DONE but one leftover | a retry can duplicate an extra attachment | S |
| #662 Back after sign-up | NOT STARTED | `pageshow` + `persisted` re-render | S |
| #520 invite landing | PARTIAL (adac2922e) | seed-link label and placement | S |
| #672 Field trust rings | PARTIAL (rings/degree/chain done) | content follows: one spaced FULL | S |
| #671 Field new Request | PARTIAL (direct contacts hinted) | refresh on show; 2nd-degree fan-out waits | S (+L deferred) |
| #459 chips and labels | PARTIAL (#614, #595) | no forced chip zoomed out, post labels, hover label | M |
| #486 Can't help | PARTIAL (Updates row + card line) | status line, Forwards fold, HUD cue | M |
| #656 question notice | PARTIAL (copy + deep link) | unread count on Questions row; Timeline text deferred | S |
| #337 Updates search | PARTIAL (semantics, no-results copy) | actor-name match on the server, Clear search | M |
| #482 poll results | PARTIAL (e0225caa5) | voterIds to author (server-only, no Hasura), voter list, closed = read-only | M |
| #658 Questions desktop | PARTIAL (Questions fixed) | Final check / Close & sum up content column; heading copy deferred | S |
| #545 first-load flicker | NOT STARTED (proposal only) | gate widget + 4 screens | L |
| #258 unread dots | PARTIAL (z2iu.23/.24) | visible Read all — waits for the missing D11 Activity spec | deferred |
| #259 self-expiring notices | NOT STARTED | needs design (classes, TTL, history) | deferred |

## Order

One linear chain. A block is one issue, so its commits stay contiguous and it
can be reverted as a whole. Security and data correctness first, cheap
first-contact fixes next, the Field block once People tags has settled, then
Requests/Updates, and the cross-screen loading gate last so it adopts screens
that already carry the other fixes.

1. #666 Post close (server guard → notice order → client)
2. #654 attachment retry
3. #662 → #520 landing
4. #672 → #671 → #459 Field
5. #486 → #656 → #337 → #482 → #658 Requests / Updates
6. #545 loading gate (widget → Request latch → Request → Activity → My Work → People)
7. Ship: version bump + full regression

Deferred (label `manual` + `needs-decision`, never dispatched): #258 Read all,
#259 expiry, #656 Timeline text, #671 second-degree hints, #658 preview
heading copy and Questions bubbles, #545 raw-spinner lint, and the owner check
on dev for the DONE issues.

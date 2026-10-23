# Realtime freshness gaps, 2026-10 (sprint lane 1)

Status: findings of the 2026-10-22 Opus sprint, lane 1 (#530 umbrella, #241,
#359, #402, #394 remainder). Branch `sprint/lane1-freshness`.

## 1. Short answer

- **Server delivery is not the problem.** For every change kind in the
  acceptance list, the hint reaches every affected account's socket
  60–350 ms after the mutation starts (dev.tentura.io, 7.42.12, light load;
  table §3).
- **Most client surfaces now converge in well under 3 s.** Measured in a real
  browser on dev against a second account acting through the API: status
  change 0.5–0.7 s, withdrawal 0.4 s, offer acceptance on Activity 0.5 s,
  untrust on People › Trusted 0.4 s (§4). The 6–24 s and "never" numbers in
  #530 were taken on 19ef4fc (2026-10-14) with 3–5 accounts acting at once;
  several fixes landed since (#516 withdrawal, #241 conversion and close,
  #495/#470 notice bars, #359 local untrust).
- **One surface had no realtime path at all: the trust graph.** It neither
  subscribed to `relationship` hints nor ever dropped a cached edge, so a trust
  change made by the other person, in another session or on another screen
  stayed drawn until a reload. Fixed (§5.1).
- **What remains is load, not plumbing:** one hint burst makes a single open
  client issue 22–64 GraphQL reads within ~1.5 s, many of them duplicates
  (§6). With 3–5 clients on the 2-vCPU dev host (`POSTGRES_MAXCONN=4`) that is
  ~150–300 reads per change, which is where the 1704 admission backoff and the
  6–9 s delays in #530 come from. Perf work is paused; this is filed, not
  tuned.

## 2. Trace method

1. **Server hint probe** (`dart run probe.dart <origin> <tag>`, dart:io only,
   kept out of the repo): logs in three QA accounts with
   `/api/v2/auth/email/test-login` (A author, B helper, C watcher), opens one
   `/api/v2/ws` socket per account, runs a scripted journey through the V2
   GraphQL API (mutual trust, create, forward, offer, accept, Enough help,
   Open, withdraw, untrust, close; a second script does Post → publish → bud)
   and records every `entity_changes` frame per account with its arrival time
   relative to the mutation start.
2. **Client end-to-end timing** (Playwright, one browser, browser lock held):
   the browser is signed in as the observing account and parked on the surface
   under test; a Playwright snippet sends the other account's mutation from the
   Node side and polls the page's semantics text (innerText + `aria-label`s)
   every 100 ms until the expected change shows, recording every GraphQL
   request the observer page makes in the window (operation, start/end ms,
   1704 flag).
3. **Code audit** of each surface's subscription (`RealtimeSyncCase` /
   repository streams → use case → cubit refetch), its stale-result guards and
   catch-up handling.
4. **New debug traces** for the next time this is chased (no behaviour
   change): server `[RealtimeFanout] realtime_event=hint_sent` at fine level
   with `received_at`/`sent_at`; client `RealtimeTiming` log lines (hint
   `recv`, batch `emit`, `catch_up`) in debug builds and
   `QA_INTEGRATION_TEST_MODE` runs.

## 3. Server hint delivery (dev, 2026-10-22, ms after mutation start)

| Change | Actor | Observer(s) | Kinds received | Arrival |
|---|---|---|---|---|
| Trust given | A | A, B | `relationship` (+ `notification` to the trusted one) | 85–90; trust-edge rewrite `relationship:update` at 1.2–3.1 s |
| Forward | A | B, C | `beacon`, `forward`, `inbox_item`, `notification` | 146–155 |
| Offer help | B | A, B, C | `help_offer`, `forward`, `relationship`, `notification` (A) | 128–141 |
| Accept offer | A | A, B; C | `help_offer`, `participant`, `beacon`, `beacon_hierarchy`, `activity_event`, `room_message`, `notification`; C: `help_offer`, `beacon` | 138–330; `constellation_field` global at 1.3 s |
| Enough help / Open | A | A, B, C | `beacon`, `beacon_hierarchy`, `activity_event`, `room_message` (members), `notification` | 103–134 |
| Withdraw | B | A, B; C | `help_offer`, `beacon`, `participant`, `activity_event`, `beacon_hierarchy`, `room_message`, `notification` (A), `inbox_item` (B); C: `help_offer`, `beacon` | 152–154 |
| Untrust | A | A, B, C | `relationship:update` | 65–66; trust-edge `relationship:update/delete` 1.8 s+ later |
| Post publish | A | B, C | `beacon`, `forward`, `inbox_item`, `beacon_hierarchy`, `participant`, `notification`, `room_message` | 264–272 |
| Bud Request from Post | A | B (invitee); C (Post member) | B: `beacon`, `forward`, `inbox_item`, `notification`, `beacon_hierarchy`, `room_message`; C: `beacon_hierarchy`, `room_message` | 159–165 |

Notes: no hint was missing for any affected account; no 1704 on the
mutations. A trust change produces two waves: the `vote_user` write at once and
the `user_trust_edge` rewrite 1–6 s later; the graph's edge source
(`graph_edges_between` → `user_trust_edge`) is only correct after the second.

## 4. Client convergence (dev, observer browser, ms after mutation start)

| Change | Observer surface | Before (19ef4fc, #530) | Now (7.42.12) | GraphQL reads in the window | 1704 |
|---|---|---|---|---|---|
| Enough help | helper, Request (HUD "YOU" line, chat line) | 6.2 s | 0.46 s (chat line), ~0.7 s (`BeaconFetchById` done) | 48 in 1.4 s | 0 |
| Withdrawal | author, Request team count | ~24 s | 0.38 s | 64 in 1.5 s | 0 |
| Offer acceptance | helper, Activity card | never | 0.53 s | 22 in 1.2 s | 0 |
| Untrust | other party, People › Trusted | — | 0.42 s | 4 | 0 |
| Untrust | other party / other session, trust graph | never | never → fixed on this branch (unit-tested; not re-measured on dev, needs a deploy) | — | — |
| Bud (convert to Request) | other Post member, open Post | reload needed (#241 case 1) | 0.31 s (the "budded" line with the new Request's title) | 19 in 1.0 s | 0 |

"Wrapping up" was not re-measured: it rides the same `beacon` hint and
`BeaconViewCubit` full refresh as Enough help.

## 5. Gap table (change kind × surface)

Legend: ✓ delivered / subscribed / refetches; ✗ gap; — not affected.
"Stale" = can an older read overwrite newer state.

| Kind → surface | Request header + People | Activity (inbox + attention) | My Work | People › Trusted | Profile | Trust graph | Field | Forward picker |
|---|---|---|---|---|---|---|---|---|
| `beacon` (status, close) | ✓ full refresh, single-flight + rerun | ✓ | ✓ | — | ✓ (shared beacons) | — | ✓ lazy | — |
| `help_offer` / `participant` (offer, accept, withdraw) | ✓ full refresh | ✓ (`helpOffer` → refetch; accept 0.5 s) | ✓ | — | — | — | ✓ | — |
| `relationship` (trust, untrust) | ✓ full refresh | — | — | ✓ refetch | ✓ refetch | **✗ → ✓ (this branch)** | ✓ via `constellation_field` global | ✗ (contract lists `forward_candidates`, `ForwardCubit` has no relationship subscription; left, §7) |
| `inbox_item` / `forward` / `notification` | ✓ | ✓ | ✓ | — | — | — | — | ✓ `forward` only |
| `beacon_hierarchy` (bud) | ✓ children/parent | — | — | — | — | — | — | — |
| reconnect catch-up | ✓ | ✓ | ✓ | ✓ | ✓ | **✗ → ✓ (this branch)** | ✓ | ✗ |
| stale overwrite guard | single-flight + generation | single-flight gate | one-shot retry | debounced refetch | sequence | **local withdrawal could be re-added by a racing read → guarded (this branch)** | revision watermark | — |

### 5.1 Trust graph (#359, #402) — fixed

- **Why the 2026-10-20 fix (6ecd039a0) did not settle it:** that fix patches
  the graph from the viewer's *own* trust toggle in the graph's person card.
  The graph still had no realtime subscription, and `_fetch` / the structural
  closure only *merge* edges into the cache, so (a) the other person's
  untrust, (b) an untrust from the People tab or profile screen while the
  graph is open, (c) another session, and (d) a reconnect never changed what
  was drawn. In addition a closure read that raced the lazy trust write could
  merge the withdrawn Me→peer edge back.
- **Fix:** `GraphCubit` (trust mode) subscribes to `relationship` hints and
  catch-ups through `RealtimeSyncCase`, batches a 250 ms window from the
  first hint (a steady stream cannot postpone it), re-reads the edges among
  all loaded people (`graph_edges_between`, same `positiveOnly` filter) and
  *replaces* them: edges the server no longer has are dropped; people whose
  link to the viewer changed (or who the hint names) are re-read in one
  `fetchProfilesByIds` so the mutual badge follows. A locally withdrawn
  Me→peer edge is not merged back from any read until the server agrees or
  20 s pass (so a re-trust from another session is not hidden for good); a
  provisional re-trust edge stays until the server has it. A neighbourhood or
  closure read that started before a re-read and lands after it schedules one
  more re-read, so an older read cannot keep a dropped edge.
- **#402 ("other connections vanish"):** the screenshot shows the focus on
  Helper Two (undo enabled, Me carries a "1 hidden" badge): tapping a person
  moves the focus-path spotlight to that person, which hides Me's other
  neighbours by design; re-trusting does not move the focus, a reload resets
  it. Nothing is dropped from the data. The data part (stale double arrow) is
  fixed; whether a tap in the trust graph should keep the ego's other
  neighbours visible is a product question for the owner, not a freshness
  bug, and is left unchanged.
- The open person card (`GraphPersonContextCubit`) re-reads the selected
  person on `ProfileViewCase.projectionChanges` (relationship, profile, block
  marker, catch-up), so its trust/visibility lines follow too; only the latest
  read is applied.
- Tests: `test/features/graph/graph_relationship_realtime_test.dart`
  (remote untrust drops the edge and badge and keeps everyone else; remote
  trust appears; burst read once; catch-up refetches; local withdrawal holds
  against a lagging server and the guard ends when it catches up).

### 5.2 #394 remainder — already fixed, now pinned

The two identical non-dismissing "Person blocked" bars came from two sibling
root Scaffolds in the wide list-detail split and from action bars that never
auto-dismissed; fixed by 200a24b31 (#495) and fa7dd8d75 (#470). A widget test
now pins it for the block flow (`block_user_sheet_test.dart`, "two-pane
profile").

### 5.3 #241 — no new gap

Case 1 (conversion) and case 2 (close status for the author) landed in
3d71e7814 / ac2883b52; case 3 (rename in the forward picker) is won't-fix
(owner, 2026-10-06). Budding (the current convert path) delivers to the
invitee and to Post members (§3).

## 6. Load: read amplification per hint burst (perf, not tuned)

One open client, one change, reads issued within ~1.5 s:

- Enough help, helper on the Request: **48 reads**, including
  `BeaconFetchById` ×1, `InboxFetch` ×5, `RoomMessageList` ×3,
  `BeaconRoomStateGet` ×3, `BeaconChildren` ×3, `AttentionFeed` ×2,
  `MyWorkInit` ×2, `BeaconParticipantList` ×2.
- Withdrawal, author on the Request: **64 reads**, including two full
  Request-detail refreshes (`BeaconFetchById` ×3, `HelpOffersWithCoordination`
  ×2, `BeaconRoomStateGet` ×5).
- Offer acceptance, helper on Activity: 22 reads. Untrust on People: 4.

Causes seen in code: (1) `BeaconViewCubit` starts a full refresh on the
`beacon` hint and then queues a *second* full refresh for the
`participant`/`help_offer`/`coordination_item` hints of the **same** batch
(they arrive while the first is in flight), although the first read already
sees that commit; (2) Activity, My Work, attention and hierarchy each refetch
independently on the same burst; (3) the debounces are per surface. On dev
(2 vCPU, `POSTGRES_MAXCONN=4`) 3–5 concurrent clients turn one change into
~150–300 reads, which matches the 1704 backoffs and 6–9 s in the 2026-10-14
session. Suggested follow-up (perf, when unpaused): treat hints delivered in
the same batch as covered by a refresh that started for that batch; share one
Inbox/My Work refetch per burst. Filed as #639.

## 7. Left / not done

- **Forward picker** does not reload candidates on `relationship` (contract
  lists `forward_candidates` as an impact). The picker is a short-lived sheet
  and the related rename case was won't-fix; left. The contract impact test
  only checks that a mapped file exists, which is how both this and the graph
  gap passed it.
- **After-measurement on dev for the graph** needs a deploy (not done in this
  lane); local acceptance is by unit test.
- Read amplification (§6), by owner decision (perf paused).

## 8. Field freshness after QA3 (#672, #671, #673) — lane FR, 2026-10-23

Branch `sprint/fr-field-freshness`. The 5-minute lazy FULL window
(`kLazyFieldRefreshInterval`) and the global `constellation_field` hint are
unchanged; no global FULL was added. `ConstellationFieldFreshnessCase` adds
targeted paths for what one viewer can see change, and the store holds what
they learn over any FULL that started earlier (released by the first FULL that
started later). Nothing is read while the field is hidden (the store refreshes
once when it is shown again).

| Change | Before | Now | Extra reads per change, per open field |
|---|---|---|---|
| Own trust write (field panel, profile, People) | lazy FULL (≤5 min) | patched on the write's ack | 0 (1 urgent FULL only when the person is not on the field yet) |
| Someone on the field changes trust with the viewer | lazy FULL | `relationship` hint → `user { my_vote trusts_viewer }` for the people the hint names (id, actor) that are on the field | 1 Hasura read (≤10 ids, no MeritRank) per 250 ms burst; the `user_trust_edge` second wave 1–6 s later costs one more |
| A direct contact publishes a discoverable Request | never (no hint) | `constellation_item` hint → `constellationFieldRequests(ids)` | 1 V2 read (≤20 ids, readability set-wise; the viewer's visible set comes from the m0235 cache, one MeritRank call on a miss — the cache is invalidated by any trust change, so misses are common under load) per burst; server: one indexed `vote_user` lookup per publish |
| Unpin after a reload | Request vanished until reload | kept as an ordinary Request | 0 |

Known costs and limits:

- The `relationship` hint goes to the endpoints' mutual friends and shared
  Request members too, and names only one endpoint plus the actor, so a viewer
  also reads when a field person changes trust with someone else (the read
  then confirms nothing changed). Bounded by one small read per burst; more
  than 20 people in one burst (a bulk recompute) is left to the lazy FULL.
- Edges between two other people, MeritRank drift and visible-set changes
  stay on the lazy FULL.
- **Second-degree audience (#671, not done):** a Request of someone the
  viewer sees only through MeritRank (Pia via Lena) still waits for the lazy
  FULL. Addressing them would need the author's visible-to set at publish
  time (a MeritRank query per publish, fan-out to up to the whole reachable
  set) — an owner decision; the client side already handles the hint for any
  author on the field.
- The hint goes to the people who trust the author (the author is a direct
  contact on their field), at most 1000, minus blocks. It tells them, by an
  opaque id, that the author published something findable, even when they
  may not read it; the follow-up read then returns nothing. Gating recipients
  by readability would need a visibility check per recipient at write time.
  Whether this metadata is acceptable is an owner call.
- Migration `m0262` is a provisional number (renumber at merge).

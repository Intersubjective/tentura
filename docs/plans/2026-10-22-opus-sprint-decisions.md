# Opus sprint 2026-10-22: ticket triage, owner decisions, lane plans

Status: **rev 2, approved for dispatch** (2026-10-22). Rev 1 was reviewed by Astra (gpt-6-astra,
high): `docs/plans/2026-10-22-opus-sprint-astra-review-rev1.md`. Rev 2 folds in every blocking and
should-fix point plus four owner answers (Q3–Q6).

## 0. Purpose and context

The owner has ~7 hours of Opus capacity (5-hour windows reset 19:49, weekly reset 02:00 CEST).
Open GitHub issues: 95. Issues labelled `good to go` are handled autonomously in the cloud by a
cheaper agent (bot PRs reviewed by Claude, r6/r7/r8 rounds) and are out of scope here, except where
noted.

Product context (2026-10-22 phase review): Tentura is pre-launch, tested only in facilitated
sessions with ~6–8 people (#72, #96, #142, #236). The failures that recur across all sessions are
**(a) comprehension of trust → visibility → relay** and **(b) live-state freshness** (things change
only after a reload). The field (constellation) is the strongest positive signal ("killer feature",
#236). Performance/scaling work is paused (owner, 2026-10-16, #553).

Raw issue bodies: `gh issue view <n> --comments`.

## 1. Triage of the open non-`good to go` issues

| Bucket | Issues | Owner |
|---|---|---|
| Freshness symptom cluster | #530 (umbrella), #241, #359, #402, #394 (snackbar remainder); stretch #545 | Opus lane 1 |
| First contact / comprehension | #252, #261, #440, #272, #248, #523, #501, #535 (rest), #520 (rest), #91 (plan only) | Opus lane 2 |
| Field as the friends list | #246, #253; then #251; #256 design-only; stretch #595, #459 | Opus lane 3 |
| Questions space | #526, #527 (offer text only if trivial), #443; PRs #543/#544 | Opus lane 4 |
| Request coordination | #479, #268 | Opus lane 5 |
| Decided and bounded → cloud | #597 (option A), #636, #474 (rest) | relabel `good to go` with a spec comment |
| Need a bounded spec before cloud | #267, #269, #271, #632 (privacy item), #634 (split: block marker → lane 1 area, release race → coordination) | integrator writes specs, then relabels |
| DB hardening, one owner | #278, #279, #280 together, transaction-focused review | cloud as one packet |
| Activity redesign | #257, #258 (rest), #259, #260 | integrator writes the spec (D11); no implementation tonight |
| Owner-only | #243 (Google billing + who owns the alert), #281 (collect rollout evidence: dev Sentry/pg_stat since 2026-10-11, then decide prod) | owner |
| Spec amendment | #189 (D12) | integrator |
| Parked | #553, #274, #227, #282 (MeritRank), #254, #255, #176 (needs real Firefox/Win10) | — |
| Close | #387 (`wontfix`); #236 stays the research umbrella | — |

`good to go` was removed on 2026-10-22 from #402, #545, #595, #459, #523, #501, #443, #535, #520
(each has a comment). The cloud agent already landed most of #507, #516, #532, #535, #520, #523
(e.g. #516: the ~24 s withdrawal delay is gone on 7.41.30), so lanes must not re-fix those.
Cloud overlaps to merge carefully: #546 (Plan tab) vs lane 5 #479; #525/#596 (My Work cards) vs
#597.

## 2. Owner decisions

| # | Issue(s) | Decision |
|---|---|---|
| D1 | #526, #527 | A Request "Questions" space, open **before** offering help, to the Request's **addressed audience** (see Q3/Q4). The whole thread is public to that audience (Q2). "Offer help" stays the commitment step. User-facing noun «Вопросы» / "Questions", not "Lobby". Reusing the dormant item-thread scope is allowed (maintainer, #526) as a named exception to "rooms are General-only"; executable guards and policy tests change with it, not only AGENTS.md. General stays private to admitted participants. |
| D2 | #597 | Option A: visible Forward CTA on the helper's Requests-tab card (`viewerCanForward`). B/C deferred. |
| D3 | #246 | Every person I directly trust is **always** on the field. One-way trust: shown as a **contact node without content** (name/avatar; their Posts/Requests only if visibility allows) (Q5). |
| D4 | #253 | List view + name search over the **same person population** as the map. Retiring the trust graph is later. |
| D5 | #251 | «Сбросить позиции» resets **all** user-placed positions (all anchor target kinds, including hidden/off-screen), **with a confirmation dialog**. |
| D6 | #252, #261 | Empty states + invite CTA + one **truthful** sentence on trust and visibility (no fixed-hop promise; visibility is mutual and MeritRank-dependent). Improve the existing info affordances (profile info button, rating tooltip, legend). Owner proofreads EN/RU copy before merge. |
| D7 | #91 | Design/plan document only. |
| D8 | #248 | Composer: message first, then recipients and "can be forwarded". Action label «Новый чат» / "New chat". A Post's conversation is user-facing "chat" (Q1); keep "Post" as the object noun. |
| D9 | #479 | After the baton author chooses the taker, offer the author "Create a plan step with <name>?" (prefilled, editable, declinable). No automatic step. |
| D10 | #268 | When the author sets «Достаточно помощи», offer **"Decline remaining offers"** (pending offers only). Admitted helpers, watchers and recipients are never removed by it. Backup offers stay allowed. |
| D11 | #257–#260 | Activity: old items collapsed, new marked, chips All/New/Watching, Watching group, self-expiring informational items, visible mark-all-**read** (distinct from dismiss). Spec tonight, build later. |
| D12 | #189 | Keep the non-forward half of §7.3 coalescing out of scope; amend `docs/plans/issue-171-card-spec.md` §7.3. Compact age stays a separate copy item. |
| — | perf | No sprint time on #553, #274, ev3z.13, or MeritRank changes. |

Owner answers (2026-10-22):

- **Q1** A post's conversation is user-facing «чат» (not a personal chat; those do not exist).
- **Q2** The Questions thread is public to the whole addressed audience.
- **Q3** Discovery-only readers (they can read a discoverable Request but it was never sent or
  forwarded to them) are **not** in the Questions audience.
- **Q4** Recipients who answered "Can't help" and helpers who withdrew keep **read-only** access.
- **Q5** One-way trust → contact node without content.
- **Q6** Direct contacts are **not capped**: they are exempt from both the server candidate cap
  (200) and the client peer budget (120); caps apply to indirect peers only. Perf impact must be
  measured on a perf fixture with many direct contacts and reported (no tuning in this sprint).

## 3. Lanes

Five Opus lanes, each in its own git worktree from `main`, each committing locally on its own
branch (`sprint/<lane>`), **no push**. The main session is the integrator: merge order, migration
numbers, version bump, full suites, dev deploy, specs for the cloud items. Paths: `server/` =
`packages/server/lib`, `client/` = `packages/client/lib`, migrations =
`packages/server/lib/data/database/migration`.

Every lane: read AGENTS.md first; client UI via the Material 3 skill and design-system lints;
user-facing nouns per `.cursor/rules/terminology.mdc`; tests only as
`flock /tmp/tentura-test.lock scripts/run_with_test_cleanup.sh <cmd> <targeted files>`; run
codegen (`build_runner`) after DI/GraphQL changes; no version bump; append ARB keys, never reorder;
at the end, a codex review (`codex exec -s read-only -m gpt-6.1-sol -c model_reasoning_effort=high`)
of the lane diff, fix findings, then report. Deliverable report: commits, tests run (exact
commands + results), what is left, copy table (if any).

### Lane 1: freshness symptom cluster (#530, #241, #359, #402, #394 rest; stretch #545)

Facts: no periodic data poll; hints are batched 100 ms (room messages 16 ms) in
`client/data/service/invalidation_service.dart:90` → `RealtimeSyncPort`/`realtime_sync_case.dart`.
One-shot retries exist (`my_work_cubit.dart:489`, `remote_api_client/retry_rejected_read.dart:26`).
Server status/withdrawal/relationship triggers exist (`m0193.dart` ~6960–7228). **1704 = admission
backoff** (`server/data/service/main_db_scope_admission.dart:111,257`, with `retryAfterMs`), not by
itself slow SQL. #359 already has local untrust patching (`graph_cubit.dart:561`) — find why it
does not hold.

1. **Trace (timebox 2 h).** Mutation completion → server hint emission → client reception → each
   retry/refetch → state emission → visible UI. Add a server-side emission timestamp to the hint
   log line (debug level) and client debug timing behind an existing debug/QA flag. Cover reconnect,
   account change and stale-response races. Reproduce on dev.tentura.io (test-login accounts) or a
   local stack with 3 browser profiles (one browser run at a time across lanes).
2. **Gap table** per change kind × surface (Request header, People tab, Activity cards, My Work,
   trust graph, field, forward picker): hint delivered? subscriber? refetch? stale overwrite?
3. **Fix** the gaps with the smallest change per surface; each with a test that hint kind K
   (or reconnect) leads to the refetch/emission. Acceptance: on an unloaded local stack, the other
   party sees status change, withdrawal, offer acceptance, untrust and convert-to-request within
   **3 s**, without reload; #359/#402 graph correct after untrust without navigation.
4. If time is dominated by 1704/admission or slow SQL, document it with numbers and file an issue;
   do not tune perf.
5. #394 rest: one auto-dismissing "Person blocked" confirmation on the two-pane layout.
6. Stretch #545: write a one-page loading-pattern proposal (first-load gate vs skeleton) only.
7. Findings note: `docs/plans/realtime-freshness-gaps-2026-10.md`.

Lane 1 owns `invalidation_service.dart`, `realtime_sync_case.dart`,
`websocket_path_entity_changes.dart` and notify triggers; other lanes do not restructure them.

### Lane 2: first contact (#252, #261, #440, #272, #248, #501, #523, #535/#520 rest; #91 plan)

1. **#252** empty states in the recipient picker (`client/features/forward/ui/widget/forward_recipient_picker.dart:780`,
   currently `noReachableContacts`/`labelNothingHere`; "Not yet seen" in `forward_scope_links.dart:135`)
   and the field (`constellation_filter_bar.dart`, `constellation_text_view.dart`). Distinguish
   empty (no contacts), filtered-empty and error. Copy: "You haven't added anyone yet" + invite CTA
   + one truthful sentence (people you trust, and who trust you back, widen whom you can see and
   send to). Coordinate with lane 3 on field files: lane 2 only touches empty-state widgets/copy.
2. **#261** improve existing affordances: legend rows in `graph/ui/widget/graph_legend_content.dart`
   (strings `app_en.arb` ~1301–1316) get one-sentence tooltips (hover + tap; never long-press only);
   profile already has an info button (`profile_view_body.dart:293`) and rating a tooltip
   (`rating_screen.dart:260`) — rewrite their text plainly. No MeritRank score on the field panel.
3. **#440** group the picker into "Your connections" (explicit direct trust) and "Others you can
   reach". No "Through X" rows: `ForwardCandidate` (`forward_candidate.dart:13`) has no intermediary
   path. The publish action at `beacon_create_screen.dart:724–737` gets truthful wording: it
   **publishes** the Request; if `isDiscoverable`, say people who can see your network may find it;
   otherwise say only people you send or forward it to will see it. Never call it "Save".
4. **#272** own invite link while signed in: plain message + copy-link; suggest a private window for tests.
5. **#248 (D8)** composer: message first, then recipients and "can be forwarded"; action «Новый чат»
   / "New chat"; terminology test; update `.cursor/rules/terminology.mdc` to state Post's
   conversation is "chat".
6. **#501** post surfaces never say "request": pass the beacon kind to shared screens
   ("How this post spread", "Forward post", …).
7. **#523** first in-app screen (`home/ui/widget/home_orientation_panel.dart`, `orientationIntro`)
   names the inviter (avatar, "<name> vouched for you", "See what <name> needs") instead of repeating
   the pager; a request-scoped invite opens that Request. Keep "How Tentura works" one tap away.
8. **#535/#520 rest**: a rename table (current → proposed, EN/RU) for owner approval; apply nothing
   from it without approval.
9. **#91**: `docs/plans/guided-first-value-scenario.md`, scenario + comprehension-test protocol
   (from `docs/plans/episode-closure-implementation-steps.md` release gate) + minimal funnel events.
10. One copy table (EN/RU, formal «вы») in the lane report for owner proofreading.

### Lane 3: field population, list/search, then reset (#246, #253, #251; #256 design-only)

Facts: server candidates = mutually visible, unblocked peers ordered by id
(`server/data/repository/constellation_anchor_projection_reader.dart:553`); first 200 taken without
direct-trust priority (`constellation_field_snapshot_reader.dart:361`). Client peer budget 120
(`client/features/constellation/domain/constellation_consts.dart:6`); holders can be dropped
(`constellation_cap_policy.dart:40`); holder composition `constellation_anchor_composition.dart:185,271`.
`ConstellationTextView` lists Request authors only (`constellation_text_view.dart:156`).

**Packet 3a — population contract (#246, Q5, Q6).**
1. Server: the field snapshot includes **all direct contacts** (people the viewer trusts, one-way
   or mutual, not blocked either way), exempt from the 200 cap; indirect peers keep the cap. A
   one-way contact that fails the visibility wall is emitted as a **contact node without content**
   (identity only: id, display name, avatar), and none of their Posts/Requests/edges beyond the
   viewer's own edge. Define it as an explicit node flag in the snapshot contract.
2. Client: direct contacts are exempt from the 120 budget and always holders; pinned/support-path
   guarantees unchanged.
3. Tests: one-way trust (contact node, no content), mutual trust, blocked either way (absent), >120
   and >200 direct contacts, pinned node, support path still present. Measure FULL time on a perf
   fixture with e.g. 300 direct contacts (`tentura_devcopy`/perfsynth local DBs exist; clone before
   destructive runs) and report numbers; no tuning.

**Packet 3b — list and search (#253, D4).** A Map/List toggle and a name search over the **same
population** as 3a (people first; a person's Posts/Requests as secondary rows). Search in Map mode
highlights and centres; in List mode filters. Replace or extend `ConstellationTextView` so it is no
longer Request-authors-only (keep its accessibility role).

**Packet 3c — reset (#251, D5), separate commit series.** Server mutation that resets all of the
viewer's anchors (all target kinds) in one transaction under the existing viewer lock, advancing
the revision watermark so delayed/in-flight placement writes with an older base are rejected
(`constellation_anchor_repository.dart:42`), idempotent on retry, and emitting the existing
`constellation_anchor` hint so other devices re-layout. Client: confirmation via
`TenturaConfirmDialog.show`; cancel/settle pending placements in `constellation_placement_case.dart:560`
before calling; re-layout. Existing "Re-arrange" (`constellation_cubit.dart:1819`) unchanged.

**#256 design-only:** a one-page read-state contract (what counts as new for a person node, what
opening clears, persistence, cross-device) in the lane report. No code.

Stretch (only if 3a–3c are done): #595 labels vanish below a zoom threshold; #459 label budget.

### Lane 4: Questions space (#526, #443; #527 only if trivial)

1. Rebase PRs #543 (server) and #544 (client) onto `main` (both ~280 commits behind). Main already
   has a different `m0253.dart`; renumber the lobby migration to the next free version (integrator
   confirms the final number at merge).
2. **One server-owned policy** `QuestionsAccess` used by open, read, history, post, edit, delete,
   react, seen, mentions, notifications and realtime delivery:
   - readable Request (existing content authorization, `m0242.dart:142`) **AND**
   - addressed audience: author; stewards; live (`cancelledAt` null) forward edge to the viewer
     (`beacon_forward_edge`); direct addressee (`beacon_participant` role 6); live help offer;
     admitted participant **AND**
   - not banned from Questions, no block with the author.
   - Write = audience minus (forward edge `recipientRejected`, withdrawn offer without other
     standing) → those are **read-only** (Q4). Historical `inbox_item` alone never authorizes.
     Discovery-only readers are excluded (Q3).
   - Cross-recipient blocks: messages of a user hidden for a viewer when either blocked the other
     (`hidden_for_viewer`, `m0193.dart:4492`).
   - Lifecycle: writable while the Request is open; read-only after close.
   - Implement as one set query (no 3×N per message).
3. #543 review should-fixes: mentions drawn from the Questions audience; author notified of
   undirected questions (attention item or unread count); realtime delivery to non-admitted
   audience members via lane 1's existing path (add scoped recipients, do not restructure).
4. #544 should-fixes: `TenturaConfirmDialog`, `TenturaEmptyState`, scoped refetch, pagination via
   `beforeIso`, names via path data not route args, rename to «Вопросы»/"Questions", glossary +
   CONTEXT.md + AGENTS.md exception updated, `docs/features` page.
5. **#443**: room empty state for the author after sending (one line + first system event).
6. Policy tests: each audience class × each operation, rejected/cancelled forwards, departed
   helper, steward, discovery-only reader denied, blocks both ways, closed Request.

### Lane 5: Request coordination (#479, #268)

1. **#479 (D9).** Make baton selection return a result carrying the resolved taker
   (`RoomCubit.batonSelect` returns `void` and swallows failures, `room_cubit.dart:1571`; automatic
   selection may have `userId == null`). Show the prompt only on a successful selection with a
   resolved taker, when the plan feature is enabled, the Request is in an editable lifecycle and the
   author may edit the plan (`beacon_plan_case.dart:958`). Append via the existing whole-plan save
   with `baseSeq` and the client's conflict rebase (`beacon_plan_case.dart:380`,
   `plan_edit_cubit.dart:85`); keep one stable step id across retries; handle a departed assignee
   and a failed save; never reopen the prompt on a realtime refresh. Fix the duplicated
   "X took it" line. Tests: simultaneous appends, conflicting edit, retry after uncertain response.
2. **#268 (D10).** "Decline remaining offers" after «Достаточно помощи»: one confirmation, one
   server call that re-checks eligibility under the same locks as admission/closure, declines only
   pending offers, settles their obligations, keeps reasons private
   (`coordination_case.dart:535` decline path). Explain the shared-chat-only model in the accept
   flow (one line).
3. Coordinate with cloud #546 (Plan tab hidden until a plan exists): the prompt creates the plan if
   none exists; do not touch tab visibility.

## 4. Integrator (main session)

- Before dispatch: this rev 2; label #597/#636/#474 `good to go` with a spec comment.
- During: specs for #267, #269, #271, #632, #634 split, then relabel; #278–#280 as one cloud
  packet; D12 amendment; D11 Activity spec (`docs/plans/activity-redesign-spec-2026-10.md`);
  review incoming bot PRs.
- Merge order: lane 1 → lane 3a → lane 2 → lane 3b → lane 4 server → lane 4 client → lane 5 →
  lane 3c. Integrator assigns migration numbers, bumps version + cache buster once per batch,
  regenerates l10n, runs both analyzer gates, server pg selections (pool-size-1, multi-connection
  `-j 1`, exclude-tags pg), client suite, web integration suite, then deploys to dev for owner QA.

## 5. File-conflict map

| Shared area | Lanes | Owner |
|---|---|---|
| `app_en.arb`, `app_ru.arb` | all | append only; integrator regenerates |
| Constellation cubit/state, filter bar, text view | 2, 3 | lane 3; lane 2 only empty-state widgets/copy |
| Forward picker, composer | 2; cloud #267 | lane 2 |
| Invalidation/realtime/websocket delivery | 1, 4 | lane 1; lane 4 adds scoped recipients only |
| Room cubit, baton | 4, 5 | lane 5 owns baton; lane 4 owns Questions files |
| Coordination/closure/plan | 5; cloud #634/#632/#546 | merge race fixes before #268 |
| Anchor repository/store/placement | 3 | lane 3 only |
| Migrations | 3, 4 | integrator numbers |
| Terminology, CONTEXT, AGENTS | 2, 4 | integrator consolidates |

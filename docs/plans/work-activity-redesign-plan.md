# My Work / Activity redesign — responsibility vs. offers

Status: design plan, revision 5. All product questions are closed (§10); D12–D13 were added with the implementation plan.

**Refined (2026-09-18).** This plan remains the record of the shipped responsibility split. Its decisions D1–D13 are refined by [`request-centric-attention-plan.md`](request-centric-attention-plan.md) and the product contract [`../features/request-attention.md`](../features/request-attention.md): D10 outcome rows become dismissible tombstones, D1's watching digest is no longer the sole entry to Watching, D5's dot-only rule now coexists with an independent My desk dot, and D7's archived-silence rule is re-stated as “the indicator predicate is the list predicate”.

Execution: [`work-activity-redesign-implementation-plan.md`](work-activity-redesign-implementation-plan.md) holds the unit manifest, the frozen contracts and the executor rules. The phase and unit tables in §8 here are a summary; the implementation plan is authoritative for order and names.

Date: 2026-09-12. Baseline: `21716a9d1` on `feature/pin_constellation`.

Relation to [`inbox-activity-ia-architecture.md`](inbox-activity-ia-architecture.md) (rev 8): this plan **keeps** its object classes (§2), prompt rules (§5), Watching as an Inbox-row collection (§4.7), per-destination feed state (§7) and My Work's obligation scope (§8, §8.1). It **supersedes** the allocation of News to Activity (§3, §2.4), the Activity body as a receipt feed with a fixed triage row above it (§4.2–§4.5), the fixed sliver order (§4.4), the first-paint budget (§4.6) and the numeric Activity badge (§6). An architecture rev 9 note must record this before code lands (§9, P0).

User-facing **Request** stays internal **Beacon**; the Activity branch stays internal `inbox`.

## 1. Product principle and decisions

**Principle (product owner):** the two tabs split information by *responsibility*.

- **My Work** — everything where I **already hold a responsibility toward others**: my obligations *and all updates about the Requests I am responsible for*.
- **Activity** — **offers to me**: new opportunities that do not require a reaction. Forwards, invite-accepted capability prompts, news from my network.

| # | Decision | Source |
|---|---|---|
| D1 | **Watching belongs to Activity** (no responsibility yet). Status changes of watched Requests appear **on the watched item**, not as separate feed rows. | product owner, 2026-09-12 |
| D2 | The **global chronological notification history with search** leaves both tabs and becomes a **secondary screen**. | product owner |
| D3 | **Trust changes and mutual connections** stay in **Activity**. | product owner |
| D4 | My Work's "Needs you" count and nav badge count **individual live obligation receipts**, not Requests. (Unchanged from arch §6.) | product owner |
| D5 | Activity's nav indicator becomes a **dot only**: offers are optional, a number nags. My Work keeps the number: obligations are owed. | product owner |
| D6 | Activity's open-offers section is labelled **«Для вас» / "For you"**. «Предложения» is never used on Activity — it collides with *help offer* («предложение помощи»). | product owner |
| D7 | Updates on **archived** own Requests are silent on the Active view and show as the card marker in the Archive filter; an obligation resurfaces the Request anyway. | product owner |
| D8 | Acting on an obligation should **settle it automatically**. Tracked as a separate server change (§8.1 S6); manual «Готово» stays until it lands. | product owner |
| D9 | «Для вас» is **uncapped: infinite scroll with live loading** — pages load as you scroll, new offers arrive in realtime. | product owner |
| D10 | **Unanswered forward cards are always pinned at the top** of «Для вас». Once acted on (offer help, forward, watch, dismiss), the card leaves the pinned zone and **drops to its chronological place** in the stream. This mirrors the prompt rule (arch §5.2–§5.3) with **no staleness demotion** for forwards. | product owner |
| D11 | **`InboxTriageRoute` is removed.** «Для вас» is the only place open forwards live. Its sort cycle (recent / MeritRank / deadline) goes with it: the pinned zone has one fixed order. | product owner |
| D12 | The new UI ships **behind a client gate** (`workActivityRedesignGate`, default off) and flips in one unit; legacy code is removed after the flip. | product owner, 2026-09-12 |
| D13 | A dismissed forward stays in the stream as **«Не интересно · Вернуть» / "Not interested · Restore"**, matching the `CONTEXT.md` term for rejections. | product owner, 2026-09-12 |

## 2. Diagnosis of the shipped state

Observed live at 390×844 (QA users `agent-1782689243-19095` — empty; `it-helper-mtx-1786881694-32` — 36 receipts, 8 live obligations) and in code.

1. **Surfaces of the same type are ordered differently on the two tabs.** My Work: receipt feed (obligations) → archive hint → Request cards. Activity: Request summary row → receipt feed, with Request-shaped tombstone cards interleaved *inside* the feed (`updates_feed_pane.dart:279-284`).
2. **My Work has two independent scroll regions at a fixed 2:3 split** (`my_work_screen.dart:377-389`). With 0 obligations ~40% of the screen reads "You have no open items that need you"; with obligations, 2.3 rows show and the third is clipped with no sign of more.
3. **One obligation renders up to three times:** a receipt row in the pane, a CTA on the card (`showReviewHelpOffersCta` / `showReviewCta`), and a "Mark done" row in Activity → All.
4. **Feed tooling on a to-do list.** The obligations pane carries "Read all", search and day grouping; none of it discharges an obligation (seen ≠ settled).
5. **The archive hint is a banner between the zones** (`my_work_finished_status_row.dart`), reads as part of the obligations, and uses raw `8` / `EdgeInsets.fromLTRB(12, 10, 4, 10)`.
6. **Activity's feed is mostly My Work content.** Local receipt mix: `relay_received` 1003, `mutual_connection_formed` 1002, `invite_accepted` 949, `request_status_changed` 733, `offer_accepted` 612, `help_offer_submitted` 567+3, `review_opened` 208, `blocker_opened` 147, `commitment_*` 131, `room_message_posted` 49, `trust_*` 62. Roughly 2,400 of ~5,700 rows are about Requests the viewer is responsible for.
7. **Forwards are shown twice** — the triage row (Inbox rows) and `relay_received` receipts — while the actual offers hide behind a one-line summary and the body is given to status churn.
8. **Chrome and copy drift:** title "Updates / Новое" vs. nav "Activity / Активность"; "36" detached from "Unread"; day headers `9/6/2026` (`updates_day_groups.dart:83`) vs. `Sep 9, 2026` on cards; one bell glyph for most kinds; a trailing hollow circle (mark seen) that reads as a checkbox next to "Mark done"; "Archive" in both My Work's filter and its only overflow item; triage copy "N requests need your response" frames an optional offer as a duty.

## 3. The routing rule

> **A receipt about a Request in my responsibility scope belongs to My Work. Everything else addressed to me belongs to Activity.**

**Responsibility scope `R(viewer)`** — a Request is in scope when the viewer:

- authored it (any status except draft; **archived included** — archive is a display preference, not a hand-over of responsibility), or
- holds an active help offer on it (`beacon_help_offer.status = 0`), or
- holds a live obligation on it (`requires_action AND settlement_kind IS NULL`, arch §8.1).

This is `MyWorkInit`'s scope (`my_work_fetch.graphql:5-40`) plus the obligation set, **without** the archive exclusion.

**Receipt → surface:**

| receipt | surface | rendered as |
|---|---|---|
| `beacon_id ∈ R`, `requires_action`, unsettled | My Work | obligation line on the Request card |
| `beacon_id ∈ R`, anything else | My Work | "what's new" line on the Request card |
| `beacon_id ∉ R`, `relay_received` with an Inbox row | Activity | **not rendered** — the Inbox row is the item: a pinned offer card while unanswered, a forward row at its chronological place afterwards (D10). The receipt only drives unseen state. |
| `beacon_id ∉ R`, Request is watched (Inbox status 1) | Activity | marker + last status on the Watching item (D1); one aggregate row in the stream (§5.3) |
| `beacon_id ∉ R`, anything else | Activity | history row |
| no beacon: `invite_accepted` | Activity | offer card (prompt, arch §5 rules) |
| no beacon: `mutual_connection_formed`, `trust_*` | Activity | history row (D3) |

**The surface is computed at read time, never stored.** Scope moves: offering help moves a forwarded Request from Activity to My Work, withdrawing moves it back, an obligation pulls an archived Request in. A stored column would be stale the moment scope changes. Name the concept `surface` — `notification_outbox.destination_kind` already exists and means the deep-link target kind (`beacon`, `profile`, `review`, …).

Overlap resolves toward My Work, as today (`home_attention_state.dart:29-30`): a forwarded Request I have also offered help on is mine.

## 4. My Work design

One `CustomScrollView`, **Request cards only**. No receipt rows anywhere on the tab.

```
┌──────────────────────────────────────┐
│ Активные ▾               Недавние ⇅  + │  ⋮ removed — Archive lives in the filter
├──────────────────────────────────────┤
│ ТРЕБУЕТ ВАС · 3                        │  section only when > 0; count = receipts (D4)
│ ┌▌ leftover-apis-32                  ┐ │
│ │▌ Закрыт · подведение итогов        │ │
│ │▌ ● Анна предложила помощь · 2ч Готово│ │  one line per live obligation (≤3, then «ещё N»)
│ │▌ ● Борис предложил помощь · 5ч Готово│ │
│ │▌ [Посмотреть предложения]          │ │  primary: existing CTA, now FilledButton.tonal
│ └▌───────────────────────────────────┘ │
│ В РАБОТЕ · 5                           │
│ ┌ reopen-loop-38                     ┐ │
│ │ Ищем помощников · 1 предложение    │ │
│ │ ● 3 новых · Анна: «завтра привезу» │ │  "what's new" row (unseen receipts)
│ └────────────────────────────────────┘ │
│ ЗАВЕРШЁННЫЕ · 2                        │
│ Остаются здесь, пока вы их не          │  helper text replaces the banner
│ архивируете.                           │
│ ┌ compact finished card ┐ [Архивировать]│
└──────────────────────────────────────┘
```

**4.1 Sections.** Applied to filters Active, All, Authored and Help offered; Drafts and Archive stay flat lists.

| section | membership | order within |
|---|---|---|
| Требует вас · N | cards with ≥1 live obligation | the chosen sort |
| В работе · N | active kinds without live obligations | the chosen sort |
| Завершённые · N | finished kinds without live obligations | the chosen sort |

A card appears in exactly one section. The header count of "Требует вас" is the number of live obligation receipts and **equals the nav badge** (D4).

**4.2 Obligation block on the card** — replaces `MyWorkObligationsPane` entirely. Each live obligation is one line: actor, event copy, age and a trailing "Готово" (`settle`). More than 3 collapse to "ещё N" (expand in place). The card's existing CTA (`showReviewHelpOffersCta` / `showReviewCta`) becomes the block's primary action. Settling the last obligation moves the card to its natural section without a refetch (`cd097c14c` already refreshes on obligation changes).

**4.3 "What's new" row** — one slot, two states. With unseen receipts: `● N новых · <latest headline>` in emphasis. Without: the existing last-event row (`my_work_last_event_row.dart`), muted. Opening the Request from the card marks its My Work receipts seen — except obligations, which stay live (seen ≠ settled).

**4.4 Archived Requests (D7).** Their non-obligation updates are silent on the Active view and show as the card marker in the Archive filter. An obligation already pulls the Request back (§8.1).

**4.5 Chrome.** Top bar: filter ▾, sort ⇅, create +. The overflow held only "Archive", which the filter already offers — remove it. The archive hint becomes the Finished section's helper text; `MyWorkFinishedArchiveHint` and its dismiss state go away.

**4.6 Empty states.** No obligations → no section, no placeholder. No cards at all → the existing orientation / empty body (`my_work_empty_body.dart`, `HomeOrientationPanel`).

## 5. Activity design

One `CustomScrollView` of **offers and network news**. No view tabs, no search, no "needs your response" copy, no urgency colour.

```
┌──────────────────────────────────────┐
│ Активность                     ✓✓  ⋮ │  ✓✓ Прочитать всё; ⋮ Наблюдаю (N), Отклонённые,
├──────────────────────────────────────┤     История уведомлений
│ ДЛЯ ВАС · 4                            │  pinned zone: every unanswered forward (D10)
│ (А) «Починить велосипед»           ✕  │  + fresh pending prompts (arch §5)
│     переслала Анна, +2 · 3ч          │
│     [Помочь]  Переслать  Наблюдать   │
│ (Б) Борис присоединился по вашему  ✕  │
│     приглашению · вчера              │
│     [Настроить доступ]  Пропустить   │
│ … pinned pages load until exhausted    │  D9
│ СЕГОДНЯ                                │  chronological stream, infinite (D9)
│ ↪ «Переезд» — переслал Глеб · 5ч      │  acted-on forward at its place, outcome shown
│   Вы наблюдаете                      │
│ ◐ Обновились 2 запроса, за которыми › │  aggregate watched-updates row (D1)
│   вы наблюдаете                      │
│ ВЧЕРА                                  │
│ ↪ «Сад» — переслала Анна              │  dismissed → D13
│   Не интересно · Вернуть             │
│ ✕ «Ремонт» закрыли до вашего ответа   │  former tombstone = forward row with that outcome
│ ⇄ Вы и Глеб теперь связаны            │  D3
│ ↑ Анна стала доверять вам больше      │
└──────────────────────────────────────┘
```

**5.1 "Для вас" — the pinned zone.** An offer is pinned while it is **open**:

- a **forward** is open ⇔ its Inbox row is `needsMe` **and** the Request is not in `R(viewer)`. An active help offer takes it out even if the row status lags ("My Work wins", §3). No staleness: an unanswered forward stays pinned until acted on, closed or deleted (D10);
- a **prompt** is open while `pending` and fresh (arch §5 unchanged: ≤2 pinned, ≥3 collapse into one row opening the batch sheet, 7-day staleness).

Pinned items share one **offer card** anatomy:

- leading avatar: who offers;
- headline: what (Request title, or person);
- supporting line: why me ("переслала Анна, +2", "присоединился по вашему приглашению");
- one `FilledButton.tonal` primary, up to two text actions, and a header ✕ dismiss;
- all targets 48dp.

Forwards keep Offer help / Forward / Watch / Dismiss (`inbox_triage_list.dart:155-172`). Prompts keep answer / skip and the setup sheet (`invite_accepted_receipt_card.dart`).

The card is **bounded**, unlike `InboxItemTile` (280–420dp in its goldens): title ≤ 2 lines, why-line 1 line, the provenance fold reduced to "+N". Requirements, deadline and room hints stay in the detail.

Order inside «Для вас»: prompts first (as above), then forwards by `latest_forward_at DESC, beacon_id DESC`. **No cap (D9)** — see §5.6. `InboxTriageRoute` and its sort cycle are removed (D11). `kPathInboxTriage` redirects to the Activity branch so old links keep working.

**Demotion (D10).** Any action that closes the offer — Offer help, Forward (the server moves the forwarder to Watching, `forward_case.dart:263-272`), Watch, Dismiss — removes the card from the pinned zone. It reappears in the stream at its **chronological place, keyed by `latest_forward_at`** (when the offer arrived, not when it was answered). There it renders as a compact **forward row** carrying the outcome: «Вы помогаете» (opens the Request, which now lives in My Work), «Вы наблюдаете», «Не интересно · Вернуть» (D13) or «Закрыт до вашего ответа». The move is server-derived — the Inbox row status changes — so it converges across devices like prompt settlement (arch §5.7). No client relocation logic.

Restore from Rejected, or a status that returns to `needsMe`, re-pins the item. A later forward from someone else updates `latest_forward_at` and moves an answered row to its new chronological place, without re-pinning.

**Motion.** If the target place is inside the loaded, visible range, the card animates to it (collapse out of the pinned zone, then insert as a row: size + fade, 200–250ms, reduced-motion → instant). Otherwise it collapses out and a SnackBar confirms the outcome with «Показать», which scrolls to the row. This reuses the existing `pendingMovedNudge` pattern (`inbox_screen.dart:73-94`).

**5.2 Chronological stream.** Day-grouped, infinite (D9). It holds:

- answered forwards (D10);
- network news (D3);
- settled or stale prompts (arch §5.3–§5.4);
- the watched-updates aggregate (§5.3);
- generic receipts about Requests outside scope.

**Tombstones dissolve into the forward row:** `closedBeforeResponse` / `deletedBeforeResponse` is just another outcome on the row at its `latest_forward_at` place. The separate 24h tombstone section and its window (arch §4.5) are superseded. Per-row dismissal (`tombstone_dismissed_at`) survives as «Скрыть» on that row.

**5.3 Watching (D1).** Stays a pushed route from ⋮ with a count (arch §4.7). Watched items gain a "new" marker and their last status line. The stream carries **one aggregate row** — "Обновились N запросов, за которыми вы наблюдаете ›" — at the time of the latest such receipt, so the Activity dot never lights for something the stream does not show. The server emits it as a synthetic `watchingDigest` item of the Activity feed (implementation plan §2.3), so it pages and sorts like any other row.

**5.4 Chrome.** Title "Активность" / "Activity", matching the nav label (arch §9). ✓✓ "Прочитать всё" is scoped to the Activity surface. ⋮ holds Watching (N), Rejected and **История уведомлений** (D2).

**5.5 First paint.** At 360×640 and 1.3× text, the first offer card is fully visible and nothing fixed sits below the app bar. This replaces arch §4.6.

**5.6 Infinite scroll and live loading (D9).** The tab is one scroll with two server-paginated sources:

1. **Pinned zone** — open forwards from a *paginated* Inbox query (§8.1 S5), 20 per page, keyset `(latest_forward_at, beacon_id)`, plus the open prompts. The header count `· N` comes from an aggregate, not from loaded rows. All pinned pages load before the stream starts.
2. **Stream** — the Activity feed (S1): activity-surface receipts **unioned with answered Inbox rows** as synthetic forward items, one keyset `(time, id)`, 50 per page. Open Inbox rows are excluded from the union, so the lift-out is a server-side filter, not client bookkeeping. `relay_received` receipts of any Beacon with an Inbox row are deduplicated into that row.

Load-more triggers within `tt.sectionGap` of the end, as `updates_feed_pane.dart:94-101` does today, with a bottom progress row per source.

**Cursor safety.** A demoted item whose key is above the stream cursor is inserted locally; one below it arrives with a later page. Either way there are no duplicates and no gaps — the same argument as arch §5.7.

**Live arrival never moves content under the user.** At the top of the scroll, a new offer inserts in place with a short fade and size transition. Scrolled down, it is held back and a «N новых ↑» pill appears; tapping it scrolls to top and inserts. Items closed elsewhere (acted on another device, closed by the author) demote with the §5.1 motion wherever they are loaded.

**Trade-off, accepted:** with many unanswered forwards, the stream sits below all of them. That is the product intent (D10). The full history stays one tap away in «История уведомлений» (D2).

## 6. Notification history screen (D2)

Repurpose `UpdatesScreen` (`features/updates/ui/screen/updates_screen.dart`, legacy route): back button, All / Unread, search, day groups — the full `UpdatesFeedPane` over **all surfaces**.

Reached from Activity ⋮. `/updates` and `/notifications` deep links (`root_router.dart:185-189`) land here instead of the Activity branch. Rows keep mark-seen / unseen and settle.

## 7. Shared visual grammar

1. Section headers everywhere use one `TenturaSectionHeader`: `typeLabel` caps, `· N` count, optional helper text.
2. Every bounded "open the full list" row uses one `TenturaAttentionSummaryRow`. Today `InboxTriageRow` (`inbox_triage_row.dart:56-95`) and `_CollapsedInvitePromptRow` (`updates_feed_pane.dart:491-514`) are near-identical copies.
3. Accent treatment is reserved for **obligations** (My Work). Activity uses neutral surfaces.
4. **History rows** (`UpdatesFeedTile`):
   - a glyph per kind — extend `updatesFeedGlyphFor` for `request_status_changed`, `offer_accepted`, `mutual_connection_formed` and `trust_*`;
   - unread shown by a leading dot and title weight; the trailing hollow circle is removed;
   - mark seen / unseen via secondary tap, a hover toolbar on pointer devices and row overflow — never long-press alone;
   - headline = event, supporting line = subject;
   - day headers "Сегодня / Вчера / 6 сентября", with the year only when it differs (locale `DateFormat.MMMd`).
5. Everything through `context.tt` tokens and `TenturaText.*`; no raw insets or radii (the removed archive hint is the current offender).

## 8. Implementation

### 8.1 Server

| unit | change | notes |
|---|---|---|
| S1 | **Surface-scoped feed and summary.** `attentionFeed(view, surface?, cursor, search)`, where `surface ∈ {my_work, activity}` and null = all (history). Summary returns `unread_total` per surface plus `needs_you_total`. For `surface = activity` the page **unions answered Inbox rows** (status ≠ `needsMe`, or Request ∈ R — any row that is not open, not dismissed-hidden) as synthetic forward items keyed `(latest_forward_at, 'inbox:'‖beacon_id)`, and dedupes `relay_received` into them (§5.6). Exact rules and ids: implementation plan UNIT 03. | SQL helper `responsibility_scope_beacons(viewer)` (§3) joined in the `visible` CTE of `attention_repository.dart:70-140`. Surface computed at read; server-side filtering keeps cursor pages full — a client-side filter would produce short or empty pages and a wrong unread total. |
| S2 | **Per-Request attention projection for My Work cards.** `myWorkAttention(beaconIds)` → per beacon: live obligation receipts (id, key, actor, createdAt, copy payload), unseen count and latest unseen receipt. | Replaces `unreadForBeacons` (`attention_repository.dart:28`) for My Work; one round trip per My Work fetch. |
| S3 | **Mark seen by Request.** `attentionMarkSeenForBeacon(beaconId)` marks every visible unseen receipt about that Request. It is surface-agnostic, because a Request is on exactly one surface at a time. Seen does not settle. | Same transactional realtime path as `markSeen`; `bridgeRoomWatermark` (`:389`) is the precedent. |
| S4 | **Scope-change invalidation.** Help offer create / withdraw, obligation arrive / settle and block / unblock must invalidate both surfaces on connected clients. | Arch impl plan §3 item 3 already lists these triggers for My Work; extend them to Activity. |
| S5 | **Paginated open offers.** A keyset-paginated Hasura query over open Inbox rows `(latest_forward_at DESC, beacon_id DESC)` plus `inbox_item_aggregate` for the count (needs `allow_aggregations` on the `user` select permission). Realtime `inboxItem` / `helpOffer` events drive insert and remove. | `InboxFetch` (`inbox_fetch.graphql`) loads every Inbox row in one request. The existing Hasura filter already hides rows with an active help offer, which is D10's definition of open. Closed-before-response rows need no query of their own: they are forward items of S1. |
| S6 | **Auto-settle on action (D8)** — *separate server change, not in P1*. Candidate rules: `help_offer_submitted` settles `resolved` when the author responds to that offer; `review_opened` settles `resolved` when that reviewer submits. | Uses the user-settlement path plus the §2.2 change notification. Needs its own short design, because partial responses and reopen interact with `superseded`. |

Tests: `@Tags(['pg'])` for the scope predicate — authored, archived-authored, active offer, withdrawn offer, obligation-only, blocked author, forward + offer overlap; per-surface summary; cursor paging under a surface filter.

### 8.2 Client

| unit | change | main files |
|---|---|---|
| C1 | DS: `TenturaSectionHeader`, `TenturaAttentionSummaryRow`; goldens | `design_system/components/` |
| C2 | Attention: surface-aware destinations (`activity` → activity surface, new `history` → all; drop `myWorkObligations`), per-surface summary, `myWorkAttention` / `markSeenForBeacon` ports | `domain/attention/attention_case.dart`, `entity/attention_feed.dart`, `feed_session_registry.dart` |
| C3 | My Work: single scroll with sections; obligation block; what's-new row; drop the pane, the 2:3 split, the archive hint and the overflow; delete `myWorkObligationsGate` (default `true` since UNIT 09) | `my_work_screen.dart`, `my_work_cards.dart`, `derive_my_work_cards.dart`, `my_work_cubit.dart`, `my_work_obligations_pane.dart` (delete), `my_work_finished_status_row.dart` (delete) |
| C4 | Activity: a new `ActivityOffersCubit` for the paged pinned zone with live arrival (§5.6); offer card, forward row and digest row; `ActivityStreamView` (pinned zone, then the stream); new top bar; the triage row, view tabs and search leave the gated body. `InboxCubit` is unchanged: it still feeds Watching (N), Watching and Rejected. | `inbox_screen.dart`, new `activity_offers_cubit.dart`, `activity_offer_card.dart`, `activity_forward_row.dart`, `activity_stream_view.dart`, `inbox_card_actions.dart`; triage route removal in cleanup (D11) |
| C5 | History screen: repurpose `UpdatesScreen`, route it, point `/updates` and `/notifications` at it | `updates_screen.dart`, `root_router.dart` |
| C6 | Nav indicators: My Work = number (live obligations) else dot (unseen my_work); Activity = dot (unseen activity, D5). This also fixes arch §1.1: invites, trust and mutual receipts now light Activity. | `home_attention_state.dart`, `home_attention_cubit.dart` |
| C7 | Navigation: `openFromUpdate` (`root_router.dart:589-593`) picks the underlying branch by `receipt.surface` instead of `preferUpdatesBranch`. OS push opens are unchanged: the payload carries `link` + `beaconId` and no push payload change is planned. Reselect = scroll to top (+ filter/sort reset on My Work, as today). The forward-success intent → Watching is unchanged (`3cad50572`). | `root_router.dart`, both screens |
| C8 | Row polish (§7.4) | `updates_feed_tile.dart`, `updates_day_groups.dart` |
| C9 | Copy + terminology: drop "ждут вашего ответа"; "Для вас" section; title "Активность"; `CONTEXT.md` §Terminology and `scripts/check-user-facing-terminology.sh`; version bump + `web/index.html` cache-buster | `l10n/app_*.arb`, `CONTEXT.md` |

### 8.3 Tests with known blast radius

Rewrite or delete:

- `test/features/my_work/my_work_obligations_pane_test.dart`
- `test/features/inbox/inbox_triage_row_test.dart`
- `test/features/graph/inbox_merit_rank_sort_test.dart` (the sort goes away with the route, D11)
- `test/features/inbox/inbox_watching_route_test.dart` (references the triage route)
- `test/features/inbox/inbox_receipts_fold_test.dart`
- `test/features/inbox/inbox_expanded_chrome_test.dart`
- `test/features/updates/updates_feed_views_test.dart`
- `test/features/updates/prompt_pinning_test.dart`
- `test/features/updates/updates_102_my_work_attention_test.dart`
- `test/features/updates/updates_feed_session_test.dart`
- `test/features/updates/cross_surface_coordination_accept_test.dart`
- `test/features/home/my_work_navbar_item_test.dart`
- `test/features/home/home_attention_cubit_test.dart`
- `test/domain/attention/attention_case_test.dart`
- `test/architecture/cross_surface_subscription_test.dart`
- `test/features/my_work/my_work_scope_coincidence_test.dart`

New goldens: offer card, My Work obligation block, section header, summary row — light/dark × ru/en × 360/390/expanded, plus a 1.3× variant.

### 8.4 Phasing

| phase | content | depends on |
|---|---|---|
| P0 | Arch rev 9 note (what §1 supersedes); terminology entry — **done 2026-09-12** (`inbox-activity-ia-architecture.md` rev 9 header + inline markers; `CONTEXT.md` Activity, Responsibility split, Needs you, For you, Notification history) | — |
| P1 | S1–S5 | P0 |
| P2 | C1 + goldens | — (parallel with P1) |
| P3 | C2, C3 — My Work | P1, P2 |
| P4 | C4, C5 — Activity + history | P3 (see below) |
| P5 | C6, C7 | P3, P4 |
| P6 | C8, C9 polish | any time after P2 |
| P7 | S6 auto-settle (own design note first) | P1 |

**Ship P3 no later than P4.** P3 alone duplicates (My Work receipts still appear in Activity) but loses nothing. P4 alone would remove My Work updates from Activity before cards can show them.

## 9. Acceptance

1. **Type purity.** My Work renders no receipt rows. Activity renders no receipt about a Request in `R(viewer)`. No Request card sits inside a receipt list.
2. **One scroll per tab**, nothing fixed below the app bar on either tab.
3. **360×640 @1.3×:** the first My Work card and the first Activity offer card are fully visible on first paint.
4. **Scope move without refresh.** Offer help on a forwarded Request → it leaves "Для вас" and appears in My Work; its next receipts land on the card. Withdraw → it returns to Activity.
5. **Counts agree.** The My Work badge equals the "Требует вас · N" header, counting receipts (D4). The Activity dot lights for `invite_accepted`, `mutual_connection_formed`, `trust_*` and watched-Request updates, and for nothing the stream does not show.
6. **Round trip** Activity → My Work → Activity restores scroll (arch §7, per destination).
7. **Pin and demote (D10).** An unanswered forward stays pinned regardless of age. Offer help / forward / watch / dismiss moves it to its `latest_forward_at` place with the right outcome label, on this device and on a second connected device without refresh. Restore-rejected re-pins it.
8. **Infinite scroll.** With 60 open offers and 120 history receipts, scrolling reaches the last history row with no duplicates and no gaps. The «Для вас · N» count is correct before all pages load.
9. **Live arrival.** A new forward arriving at scroll offset 0 appears in place. Arriving while scrolled down, it shows the «N новых ↑» pill and shifts no visible content.
10. `scripts/check-custom-lints.sh` shows no new violations; `flutter test` is green; goldens are reviewed.

## 10. Questions — closed 2026-09-12

| # | question | answer |
|---|---|---|
| Q1 | Activity nav indicator | dot only → D5 |
| Q2 | Label for "offers to me" | «Для вас» → D6 |
| Q3 | Updates on archived own Requests | silent on Active, marker in Archive → D7 |
| Q4 | Auto-settle an obligation on action | yes, as a separate server change → D8, S6, P7 |
| Q5 | Cap for «Для вас» | none: infinite scroll with live loading → D9, §5.6, S5 |

D10 (added after Q5) fixes the stream model: open forwards pinned, answered forwards at their chronological place (§5.1, §5.6).

`InboxTriageRoute` is removed (D11). No open questions remain.

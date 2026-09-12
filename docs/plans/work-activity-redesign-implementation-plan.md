# My Work / Activity redesign — implementation plan

Status: implementation plan, revision 1. Executable by the overseer skill (one fresh worker per unit, strictly sequential).

Date: 2026-09-12. Written against HEAD `d84acc940` on `feature/pin_constellation`.

Design source: [`work-activity-redesign-plan.md`](work-activity-redesign-plan.md) (rev 5, decisions D1–D13). This document says **how**, in what order, and how to prove it. When the two disagree on behaviour, the design plan wins; when either disagrees with live code, rule 4 of §3 applies.

Journal: [`work-activity-redesign-implementation-journal.md`](work-activity-redesign-implementation-journal.md), created by UNIT 00.

User-facing **Request** = internal **Beacon**. User-facing **Activity** = internal `inbox`. No parallel `Request` or `Activity` entity, table or route family.

## 1. Shipping sequence

1. **Server, additive** (UNITs 01–06). New SQL function, new arguments and fields, one Hasura metadata flag. Old clients keep working: every change is an optional argument, a new field or a new query.
2. **Client foundations** (UNITs 07–10). Data layer, `AttentionCase`, the redesign gate, design-system components, row polish.
3. **My Work behind the gate** (UNITs 11–13).
4. **Activity behind the gate** (UNITs 14–19).
5. **Flip** (UNIT 20), then **cleanup** (UNIT 21), then **release** (UNIT 22).

**Gate rule.** From UNIT 09 until UNIT 20, every user-visible change mounts only when `readWorkActivityRedesignGateEnabled()` returns `true`. The default is `false`. The only exception is UNIT 10 (row polish), which is allowed to change existing surfaces. If any other unit in 09–19 changes what a user sees with the gate off, it is wrong.

**Not in this manifest:** design-plan S6 (auto-settle an obligation when the user acts on it, D8). It needs its own short design note first, because partial responses and reopen interact with `superseded`.

## 2. Frozen contracts (do not rename)

Names an executor must use verbatim. Names *chosen* here rather than already existing are marked **new**.

### 2.1 Migrations

The highest present migration is `m0167` (`_migrations.dart:173` part line, `:343` list entry). Next free: **`m0168`**. Register it in both places. Never renumber a landed migration.

| id | purpose | unit |
|---|---|---|
| `m0168` **new** | `public.responsibility_scope_base_beacons(p_account_id text) RETURNS TABLE(beacon_id text)` | 01 |

### 2.2 Responsibility scope — one definition

`R(viewer)` = **base** ∪ **obligations**:

- **base** (SQL function, m0168): Beacons with `beacon.user_id = viewer AND beacon.status <> 2`, ∪ Beacons with a `beacon_help_offer` row `user_id = viewer AND status = 0` whose beacon has `status <> 2`. (`status = 2` is deleted, `3` is draft — `m0162.dart:16-17`.) Archive state is **ignored**: archived authored Beacons are in scope.
- **obligations**: `beacon_id` of visible receipts with `requires_action AND settlement_kind IS NULL`. Always taken from the **same** `visible_attention_receipts` relation the calling query already computes (`m0117.dart:7-66`). **Never a second authorization path**, and never a second call to `visible_attention_receipts` in one statement.

A receipt's **surface** is `myWork` when `beacon_id ∈ R`, otherwise `activity` (Beacon-less receipts are always `activity`). It is computed per read, never stored. It is unrelated to `notification_outbox.destination_kind`, which is the deep-link target kind.

### 2.3 Server GraphQL (V2, additive; stitched by Hasura with the `v2_` prefix)

| name | shape | unit |
|---|---|---|
| `attentionFeed(..., surface: String)` | new optional arg; `'myWork'` \| `'activity'` \| null (= all surfaces, today's behaviour). `search` must be null when `surface = 'activity'` (ArgumentError). | 02, 03 |
| `AttentionReceipt.surface` **new** | `String!` — `'myWork'` \| `'activity'` | 02 |
| `AttentionReceipt.itemKind` **new** | `String!` — `'receipt'` \| `'forward'` \| `'watchingDigest'`; always `'receipt'` unless `surface = 'activity'` | 02 (field), 03 (values) |
| `AttentionReceipt.forwardOutcome` **new** | `String` — `'helping'` \| `'watching'` \| `'notInterested'` \| `'closedBeforeResponse'` \| `'deletedBeforeResponse'`; non-null only on `forward` items | 03 |
| `AttentionReceipt.forwardCount` **new** | `Int` — `inbox_item.forward_count` on `forward` items | 03 |
| `AttentionReceipt.digestCount` **new** | `Int` — number of watched Beacons with unseen receipts, on the single `watchingDigest` item | 03 |
| `AttentionSummary.unreadTotal` | unchanged name; now scoped to the requested `surface` (all surfaces when null) | 02 |
| `attentionSurfaceSummary` **new** | `AttentionSurfaceSummary! { activityUnreadTotal: Int!, myWorkUnreadTotal: Int!, needsYouTotal: Int! }` | 02 |
| `attentionMarkAllSeen(surface: String)` | new optional arg; null = all (today's behaviour) | 02 |
| `attentionMarkSeenForBeacon(beaconId: String!)` **new** | `Int!` — marks every visible unseen receipt about that Beacon seen. Surface-agnostic: a Beacon is on exactly one surface at a time. Seen ≠ settled. | 04 |
| `myWorkAttention(beaconIds: [String!]!)` **new** | `[MyWorkBeaconAttention!]!`, ≤ 500 unique ids (same guard as `attentionMarkers`, `query_attention.dart:44-50`). `MyWorkBeaconAttention { beaconId: String!, unseenCount: Int!, latestUnseen: AttentionReceipt, liveObligations: [AttentionReceipt!]! }`. Returns only Beacons in `R` with `unseenCount > 0` or ≥ 1 live obligation. `latestUnseen` excludes live obligations. | 05 |

Synthetic items (`forward`, `watchingDigest`) are rows of the **same** `AttentionReceipt` type so one keyset cursor covers the stream. Their ids are frozen: `inbox:<beaconId>` and `watching-digest`.

Server-internal model enums stay valid: synthetic forward items use `NotificationKind.newRelay`, and the digest uses the kind stored for `request_status_changed` (`roomActivityLowPriority` in live data). If the model cannot represent them without inventing a kind, the unit stops with `BLOCKED`.

### 2.4 Hasura

| change | unit |
|---|---|
| `inbox_item` select permission for role `user`: add `"allow_aggregations": true`. Keep the existing filter unchanged: `user_id = X-Hasura-User-Id AND NOT inbox_user_help_offer.status = 0`. | 06 |

That existing filter already hides rows where the viewer holds an active help offer. This is exactly the D10 definition of an **open** forward, together with `status = 0` and `beacon.can_read_content`.

### 2.5 Client identifiers

| name | value | unit |
|---|---|---|
| gate **new** | `workActivityRedesignGate` (`@Named` bool, default `false`), reader `readWorkActivityRedesignGateEnabled()`, file `lib/features/home/domain/work_activity_redesign_gate.dart`; pattern `my_work_obligations_gate.dart:1-21` | 09 |
| surface enum **new** | `enum AttentionSurface { myWork, activity }` in `domain/attention/entity/attention_feed.dart`; wire names `'myWork'`, `'activity'` | 07 |
| item kind enum **new** | `enum AttentionItemKind { receipt, forward, watchingDigest }`, same file | 07 |
| destination ids **new** | `AttentionFeedDestinationId.activityStream = 'activity_stream'` (surface activity), `AttentionFeedDestinationId.history = 'notification_history'` (surface null). The existing `activity` and `myWorkObligations` stay until UNIT 21. | 08 |
| route **new** | `kPathInboxHistory = '$kPathInbox/history'` → `UpdatesRoute` (already generated, `root_router.gr.dart:1751`, **not** registered today) | 18 |
| redirects | UNIT 20: `kPathUpdates` → `kPathInboxHistory`. UNIT 21: `kPathInboxTriage` → `kPathInbox`. `kPathNotifications` → `kPathUpdates` unchanged. | 20, 21 |
| GraphQL fragment **new** | `InboxItemFields` on `inbox_item`, extracted from `inbox_fetch.graphql:8-26`, reused by `InboxFetch` and the new `ActivityOffers` query | 14 |
| DS components **new** | `TenturaSectionHeader`, `TenturaAttentionSummaryRow` in `lib/design_system/components/`, exported from the barrel | 09 |
| Activity widgets **new** | `ActivityOfferCard`, `ActivityForwardRow`, `ActivityWatchingDigestRow`, `ActivityStreamView` under `lib/features/inbox/ui/widget/`; `ActivityOffersCubit` under `lib/features/inbox/ui/bloc/`; card action helpers moved to `lib/features/inbox/ui/widget/inbox_card_actions.dart` | 14–16 |
| My Work widgets **new** | `MyWorkObligationBlock`, `MyWorkWhatsNewRow` in `lib/features/my_work/ui/widget/`; `deriveMyWorkSections` in `lib/features/my_work/domain/derive_my_work_sections.dart` | 12, 13 |

**Test ids.** Activity ids are dashed, like their neighbours (`test_ids.dart:21-26`). My Work ids are dotted (`:31-37`).

- **Activity:** `activity-offer-$beaconId`, `activity-forward-row-$beaconId`, `activity-watching-digest`, `activity-new-items-pill`, `activity-for-you-header`.
- **My Work:** `my_work.section.needs_you`, `my_work.section.in_progress`, `my_work.section.finished`, `my_work.obligation.$receiptId`, `my_work.whats_new.$beaconId`.

### 2.6 Copy (new l10n keys, EN / RU)

| key | EN | RU |
|---|---|---|
| `activityForYouTitle` | For you | Для вас |
| `activityNewItemsPill` | `{count, plural, one{1 new} other{{count} new}}` ↑ | `{count, plural, one{{count} новое} few{{count} новых} many{{count} новых} other{{count} новых}}` ↑ |
| `activityForwardOutcomeHelping` | You're helping | Вы помогаете |
| `activityForwardOutcomeWatching` | You're watching | Вы наблюдаете |
| `activityForwardOutcomeNotInterested` | Not interested | Не интересно |
| `activityForwardOutcomeClosed` | Closed before you answered | Закрыт до вашего ответа |
| `activityForwardOutcomeDeleted` | No longer available | Больше недоступен |
| `activityForwardRestore` | Restore | Вернуть |
| `activityWatchingDigest` | plural: `{count} requests you watch were updated` | plural: `Обновились {count} запроса, за которыми вы наблюдаете` (one/few/many/other) |
| `activityMovedToStream` | Moved to the stream | Перемещено в ленту |
| `activityShowInStream` | Show | Показать |
| `notificationHistoryTitle` | Notification history | История уведомлений |
| `myWorkSectionNeedsYou` | Needs you | Требует вас |
| `myWorkSectionInProgress` | In progress | В работе |
| `myWorkSectionFinished` | Finished | Завершённые |
| `myWorkObligationDone` | Done | Готово |
| `myWorkObligationMore` | plural: `{count} more` | plural: `ещё {count}` |
| `myWorkWhatsNew` | plural: `{count} new · {headline}` | plural: `{count} новых · {headline}` |

- Finished-section helper text reuses the existing value of `myWorkFinishedHint`.
- The Activity title reuses the existing `inbox` key.
- **Forbidden on Activity:** «Предложения» / "Offers" (collides with *help offer*) and obligation wording («ждут вашего ответа» / "need your response"). See `CONTEXT.md` §My desk.

## 3. Executor contract

1. **Units run in manifest order, strictly sequentially.** Several units share `attention_repository.dart` (server and client), `attention_case.dart`, `custom_types.dart`, `inbox_screen.dart` and `my_work_screen.dart`. The order is what keeps them from colliding. The depends-on column records *why*; it does not license reordering.
2. **An Owns list is a starting point, not an inventory.** Before editing, confirm each path exists. If one does not, or the wiring differs from what the unit describes, apply rule 4. Do not search for "the file it probably meant" and continue.
3. **Preserve pre-existing changes.** At baseline: `CONTEXT.md` and `docs/plans/inbox-activity-ia-architecture.md` (P0 doc edits, may already be committed), `packages/force_directed_graphview/analysis_options.yaml`, and 35 untracked paths. Stage explicit paths only. Never `git add -A`, stash or reset.
4. **If live code contradicts a frozen contract (§2), stop the unit** and record `BLOCKED` with the contradicting evidence. Do not adapt the contract silently.
5. **Run codegen after GraphQL / Freezed / Drift / AutoRoute / Injectable / `.arb` changes.** Never hand-edit generated output.
   - Client: `dart run build_runner build -d`.
   - Server: `dart run build_runner build -d`.
   - l10n: `flutter gen-l10n` (config `packages/client/l10n.yaml`).
   - A client unit that consumes a **new server field** must first refresh the SDL: server running, then `docker compose run --rm schema_fetcher` (see `test/data/gql/direct_v2_schema_overlay_test.dart:6-10`). Only then run codegen. Ferry generates from `lib/data/gql/schema.graphql` (`build.yaml:32`).
6. **Every Verify line runs from the repository root unless it `cd`s, as its own command.** They are a checklist, not a script.
7. **`-t pg` tests skip silently when Postgres is unreachable** (`attention_repository_pg_test.dart:28-33`). A pg Verify line that reports zero executed tests is a **failed** unit.
8. **Do not "fix" a failing assertion by editing the expectation.** Record whether it is a genuine regression or an assertion that encoded the old behaviour. Only the latter may change, and the journal names it.
9. **Lints:** `./scripts/check-custom-lints.sh packages/client` (or `packages/server`). Re-read `scripts/custom-lint-baseline.txt` before judging a count: the baseline only drifts down. No new violations in touched files. Design-system rules: tokens only, no raw `EdgeInsets`/`BorderRadius`/`fontSize`/`Color`, `TenturaText.*` for type (see `.claude/skills/material-3-flutter/SKILL.md`).
10. **Gate rule of §1.** Tests for gated UI register the gate as `true` via GetIt. Tests for legacy UI keep it `false`.
11. **One focused commit per completed coherent step**, and at least one per unit, using the suggested subject. Commits stay local: no push.
12. **Goldens:** regenerate intentionally with `flutter test --update-goldens <path>`, then open and eyeball the PNG. Pattern: `test/features/inbox/inbox_item_tile_golden_test.dart`.

Journal entry template:

```markdown
## UNIT <id> — <complete|partial|blocked> — <ISO date>
COMMITS: <hash and subject, or none>
TESTS: <exact command and outcome, with executed/skipped counts for -t pg>
FILES: <paths>
FINDINGS: <live facts that differed from the plan, or none>
DECISIONS: <anything this unit resolved that §2 did not fix>
REMAINING: <specific work, or none>
```

## 4. Unit manifest

| Unit | Purpose | Design ref | Depends on | Suggested commit |
|---|---|---|---|---|
| 00 | Journal, baseline, preflights | — | — | `docs: start work/activity redesign journal` |
| 01 | Server: responsibility scope base function — m0168 | §3 | 00 | `feat(server): add the responsibility scope function` |
| 02 | Server: surface on the attention feed, summary and mark-all | §3, S1 | 01 | `feat(server): scope attention reads by surface` |
| 03 | Server: forward and watching-digest items on the activity surface | §5.1–5.3, §5.6 | 02 | `feat(server): fold answered forwards into the activity stream` |
| 04 | Server: mark seen by Request | S3 | 02 | `feat(server): mark a request's receipts seen` |
| 05 | Server: My Work per-Request attention projection | S2 | 02 | `feat(server): expose per-request attention for my work` |
| 06 | Hasura: `inbox_item` aggregations | S5 | 00 | `chore(hasura): allow inbox item aggregations` |
| 07 | Client: schema refresh and attention data layer | S1–S3 | 02–06 | `feat(client): read attention by surface` |
| 08 | Client: `AttentionCase` surfaces, summary and invalidation | S4, C2 | 07 | `feat(client): surface-aware attention sessions` |
| 09 | Client: redesign gate and design-system components | §7, C1 | 00 | `feat(client): add section header and summary row` |
| 10 | Client: history row polish (ungated) | §7.4, C8 | 09 | `fix(client): clarify notification rows` |
| 11 | Client: My Work attention state | §4.2–4.3 | 08 | `feat(client): load per-request attention in my work` |
| 12 | Client: My Work obligation block and what's-new row | §4.2–4.3 | 09, 11 | `feat(client): show obligations and news on my work cards` |
| 13 | Client: My Work sectioned body | §4.1, §4.5–4.6 | 12 | `feat(client): section my work by responsibility` |
| 14 | Client: Activity offers cubit (paged pinned zone) | §5.1, §5.6 | 06, 08 | `feat(client): page open forwards for activity` |
| 15 | Client: offer card, forward row, digest row | §5.1–5.3 | 09, 14 | `feat(client): activity offer card and stream rows` |
| 16 | Client: Activity stream view | §5, §5.6 | 10, 15 | `feat(client): make activity one stream of offers` |
| 17 | Client: live arrival and demotion motion | §5.1, §5.6 | 16 | `feat(client): demote answered forwards into the stream` |
| 18 | Client: Activity chrome and notification history route | §5.4, §6 | 16 | `feat(client): activity chrome and notification history` |
| 19 | Client: nav indicators and surface-aware open | §6, C6, C7 | 08, 18 | `feat(client): badge by responsibility surface` |
| 20 | **Flip** the gate, redirects, e2e helpers, first-paint proofs | §9 | 13, 17, 19 | `feat(client): ship the work/activity redesign` |
| 21 | Cleanup: legacy paths, both gates, triage route | D11, §8.3 | 20 | `chore(client): remove the legacy work/activity surfaces` |
| 22 | Release: version, cache-buster, acceptance matrix | §9 | 21 | `chore(client): release the work/activity redesign` |

---

## UNIT 00 — Journal, baseline, preflights

**Owns:**

```text
docs/plans/work-activity-redesign-implementation-journal.md   new
```

1. Create the journal with a baseline entry:
   - `git rev-parse --short HEAD`;
   - the revisions of both plan documents;
   - `flutter --version` and `dart --version`;
   - the pre-existing modified and untracked paths (`git status --short`).
2. **Postgres preflight.** Run the Verify pg line and record the executed-test count. Zero executed tests means the preflight failed: fix the database target first. The connection pattern is `packages/server/test/support/beacon_hierarchy_fixture.dart:485-500`.
3. **Schema-fetch preflight.** With the local stack up (`./scripts/dev-up.sh`, or the server via `scripts/run-server-local.sh`), run `docker compose run --rm schema_fetcher` and confirm `git diff --stat packages/client/lib/data/gql/schema.graphql` is empty or explainable. Record how the stack was started.
4. Record the current custom-lint counts for `packages/client` and `packages/server` against `scripts/custom-lint-baseline.txt`.

**Verify:**

```bash
git status --short
cd packages/server && dart test -t pg -j 1 test/data/repository/attention_repository_pg_test.dart
./scripts/check-custom-lints.sh packages/client
./scripts/check-custom-lints.sh packages/server
```

**Acceptance:** the journal exists with a baseline, the pg suite provably executes, and schema fetch works. No code touched.

---

## UNIT 01 — Server: responsibility scope base function (m0168)

Implements design §3, §2.2 here.

**Owns:**

```text
packages/server/lib/data/database/migration/m0168.dart                       new
packages/server/lib/data/database/migration/_migrations.dart                 edit
packages/server/test/data/repository/responsibility_scope_pg_test.dart      new
```

1. Write `m0168` in the style of `m0167.dart` (`part of '_migrations.dart'`, `final m0168 = Migration('0168', [...])`). Create `public.responsibility_scope_base_beacons(p_account_id text) RETURNS TABLE(beacon_id text)`:
   - `LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp`, like `visible_attention_receipts` (`m0117.dart:7-14`);
   - body: the **base** set of §2.2 as a `UNION` of the authored and help-offer sets.
2. Register it (`_migrations.dart:173` and `:343`).
3. pg tests. Membership:
   - authored open → in;
   - authored **archived** → in;
   - authored deleted (`status = 2`) → out;
   - active help offer (`status = 0`) → in;
   - withdrawn offer → out;
   - help offer on a deleted beacon → out;
   - forward-only recipient → out;
   - both authored and offered → one row.

**Verify:**

```bash
cd packages/server && dart test -t pg -j 1 test/data/repository/responsibility_scope_pg_test.dart
./scripts/check-custom-lints.sh packages/server
```

**Acceptance:** the function returns exactly the base set. Nothing calls it yet.

---

## UNIT 02 — Server: surface on the attention feed, summary and mark-all

Implements design §3 and S1 (receipts only; synthetic items are UNIT 03).

**Owns:**

```text
packages/server/lib/domain/attention/attention_models.dart                    edit
packages/server/lib/domain/port/attention_query_port.dart                     edit
packages/server/lib/domain/port/attention_ack_port.dart                       edit
packages/server/lib/data/repository/attention_repository.dart                 edit
packages/server/lib/api/controllers/graphql/custom_types.dart                 edit
packages/server/lib/api/controllers/graphql/query/query_attention.dart        edit
packages/server/lib/api/controllers/graphql/mutation/mutation_attention.dart  edit
packages/server/test/api/controllers/graphql/attention_graphql_test.dart      edit
packages/server/test/domain/attention/legacy_canonical_compat_fixture_test.dart  edit
packages/server/test/data/repository/attention_surface_pg_test.dart           new
```

1. **Model.**
   - Add `enum AttentionSurface { myWork, activity }` with wire names `'myWork'` / `'activity'`.
   - Add `enum AttentionItemKind { receipt, forward, watchingDigest }`.
   - On the server `AttentionReceipt` (`attention_models.dart:281`), add `surface` (required), `itemKind` (default `receipt`) and the nullable `forwardOutcome`, `forwardCount`, `digestCount`.
   - Add `AttentionSurfaceSummary`.
2. **Port.**
   - `attentionFeed` gains `AttentionSurface? surface` (`attention_query_port.dart:7-13`).
   - Add `Future<AttentionSurfaceSummary> surfaceSummary({required String accountId})`.
   - `AttentionAckPort.markAllSeen` gains `AttentionSurface? surface`.
3. **Repository** (`attention_repository.dart:70-175`):
   - in the `visible` CTE, compute `scope` = `responsibility_scope_base_beacons($1)` ∪ obligation beacon ids from `visible` itself (§2.2 — no second `visible_attention_receipts` call);
   - add a `surface` column: `CASE WHEN visible.beacon_id IS NOT NULL AND visible.beacon_id IN (SELECT beacon_id FROM scope) THEN 'myWork' ELSE 'activity' END`;
   - filter `page` and the `summary` `unread_total` by `surface` when non-null; `needs_you_total` stays unfiltered (obligations are `myWork` by definition);
   - `_mapRow` reads `surface` and sets `itemKind = receipt`;
   - `surfaceSummary` returns both unread totals plus `needs_you_total` from one statement;
   - `markAllSeen(surface)` restricts the `UPDATE` (`:372-387`) to receipts of that surface using the same scope expression.
4. **GraphQL.**
   - Add the fields and types of §2.3 to `custom_types.dart:121-176` (`AttentionReceipt` fields, `AttentionSurfaceSummary` type).
   - `attentionFeed` gains the `surface` arg: parse it, reject unknown values, reject a non-null `search` together with `surface = 'activity'`.
   - Add the `attentionSurfaceSummary` query; `_mapReceipt` (`query_attention.dart:176-207`) emits the new fields.
   - `attentionMarkAllSeen` gains `surface` (`mutation_attention.dart:67-72`).
5. **Every plain implementer of the ports breaks.** Update `test/api/controllers/graphql/attention_graphql_test.dart:19` and `:87`, and `test/domain/attention/legacy_canonical_compat_fixture_test.dart:124`.
6. **pg tests:**
   - authored → `myWork`; archived-authored → `myWork`; active offer → `myWork`;
   - obligation-only Beacon (formerCommitter review) → `myWork`;
   - forward-only → `activity`; Beacon-less `invite_accepted` → `activity`;
   - withdrawn offer → `activity`;
   - per-surface `unreadTotal`; `needsYouTotal` unchanged;
   - `markAllSeen(activity)` leaves `myWork` receipts unseen;
   - `surface: null` returns exactly today's page and totals;
   - cursor paging under a surface filter: no duplicates, no gaps across 3 pages.

**Verify:**

```bash
cd packages/server && dart run build_runner build -d
cd packages/server && dart test -t pg -j 1 test/data/repository/attention_surface_pg_test.dart test/data/repository/attention_repository_pg_test.dart
cd packages/server && dart test test/api/controllers/graphql/attention_graphql_test.dart test/api/controllers/graphql/query_attention_payload_test.dart
./scripts/check-custom-lints.sh packages/server
```

**Acceptance:** feed and summary can be read per surface; the null-surface read is byte-for-byte today's behaviour.

---

## UNIT 03 — Server: forward and watching-digest items on the activity surface

Implements design §5.1–5.3, §5.6 and D10.

**Owns:**

```text
packages/server/lib/data/repository/attention_repository.dart          edit
packages/server/test/data/repository/attention_activity_stream_pg_test.dart  new
```

Only when `surface = 'activity'`, the page becomes a `UNION ALL` of three parts, all keyed `(created_at, id)` under the existing cursor (`:84-95`).

1. **Receipts** on the activity surface, **excluding** any receipt whose `beacon_id` has an `inbox_item` row for the viewer. Those receipts are represented by the Inbox row (design §3).
2. **Forward items**, one per `inbox_item` row of the viewer where:
   - the row is **not open**: `status <> 0`, **or** the Beacon ∈ `R` (the helping case, where the row status may lag);
   - `tombstone_dismissed_at IS NULL`;
   - `beacon_can_read_content(beacon_id, $1)`, **or** `status IN (3, 4) AND beacon_can_read_tombstone(beacon_id, $1)`.

   Each forward item has:
   - `id = 'inbox:' || beacon_id`, `created_at = latest_forward_at`, `item_kind = 'forward'`, `surface = 'activity'`;
   - `forward_outcome`: `helping` (∈ `R`) › `watching` (1) › `notInterested` (2) › `closedBeforeResponse` (3) › `deletedBeforeResponse` (4), in that precedence;
   - `forward_count` from the row;
   - `seen_at` NULL iff the Beacon ∉ `R` and a visible unseen `relay_received` receipt exists for it; otherwise non-null (use `latest_forward_at`);
   - title from the Beacon when content is readable; otherwise the tombstone copy flag and an empty title.
3. **Watching digest**: at most one row, `id = 'watching-digest'`, present only when ≥ 1 watched Beacon (Inbox status 1, ∉ `R`) has a visible unseen receipt. `created_at` = the newest such receipt, `digest_count` = the number of such Beacons, `seen_at` NULL.

Summary `unread_total` for `activity` still counts **unseen activity-surface receipts**, including the ones represented by Inbox rows. Each of them is visible through its representative: pinned card, forward row or digest.

**pg tests:**
- open forward absent from the page;
- watch / reject / offer-help each produce one forward item with the right outcome, at `latest_forward_at`;
- `closedBeforeResponse` and `deletedBeforeResponse` outcomes appear; `tombstone_dismissed_at` hides the row;
- relay receipts are deduped into the forward item;
- the digest appears and counts Beacons, not receipts;
- **cursor safety**: 60 receipts + 20 forward items across 3 pages → no duplicates, no gaps, strictly descending `(created_at, id)`;
- a demoted row whose key is above the cursor is returned by a head refetch; one below it arrives with a later page;
- `unread_total` matches the sum defined above.

**Verify:**

```bash
cd packages/server && dart test -t pg -j 1 test/data/repository/attention_activity_stream_pg_test.dart test/data/repository/attention_surface_pg_test.dart
./scripts/check-custom-lints.sh packages/server
```

**Acceptance:** the activity page is the design's stream: answered forwards at their chronological place, no open forwards, no represented receipts.

---

## UNIT 04 — Server: mark seen by Request

Implements S3.

**Owns:**

```text
packages/server/lib/domain/port/attention_ack_port.dart                       edit
packages/server/lib/data/repository/attention_repository.dart                 edit
packages/server/lib/api/controllers/graphql/mutation/mutation_attention.dart  edit
packages/server/test/api/controllers/graphql/attention_graphql_test.dart      edit
packages/server/test/data/repository/attention_mark_seen_for_beacon_pg_test.dart  new
```

1. Add `markSeenForBeacon({required String accountId, required String beaconId})` to `AttentionAckPort`, beside `bridgeRoomWatermark` (`attention_ack_port.dart:15-20`).
2. Implement it like `markSeen` (`attention_repository.dart:295-326`): `seen_at = COALESCE(seen_at, now())` for this account's unseen receipts with `beacon_id = $2` that are in `visible_attention_receipts($1)`. **Settlement columns untouched.**
3. Expose `attentionMarkSeenForBeacon(beaconId: String!): Int!`.
4. Update the fake at `attention_graphql_test.dart:87`.
5. pg tests:
   - marks only that Beacon;
   - leaves live obligations live (`settlement_kind` still NULL);
   - ignores receipts the viewer cannot see;
   - the change reaches the realtime change-detection path. `seen_at` is in the tuple (`m0116`); assert the trigger fires the same way `markSeen` does.

**Verify:**

```bash
cd packages/server && dart test -t pg -j 1 test/data/repository/attention_mark_seen_for_beacon_pg_test.dart
cd packages/server && dart test test/api/controllers/graphql/attention_graphql_test.dart
./scripts/check-custom-lints.sh packages/server
```

**Acceptance:** one call marks a Request's receipts seen without settling anything.

---

## UNIT 05 — Server: My Work per-Request attention projection

Implements S2.

**Owns:**

```text
packages/server/lib/domain/attention/attention_models.dart                  edit
packages/server/lib/domain/port/attention_query_port.dart                   edit
packages/server/lib/data/repository/attention_repository.dart               edit
packages/server/lib/api/controllers/graphql/custom_types.dart               edit
packages/server/lib/api/controllers/graphql/query/query_attention.dart      edit
packages/server/test/api/controllers/graphql/attention_graphql_test.dart    edit
packages/server/test/domain/attention/legacy_canonical_compat_fixture_test.dart  edit
packages/server/test/data/repository/my_work_attention_pg_test.dart         new
```

1. Model `MyWorkBeaconAttention` and port method `myWorkAttention({accountId, beaconIds})`.
2. One statement over `visible` (§2.2 rule), restricted to `beaconIds ∩ R`:
   - `unseenCount` = unseen receipts;
   - `latestUnseen` = newest unseen receipt that is **not** a live obligation;
   - `liveObligations` = `requires_action AND settlement_kind IS NULL`, any seen state, newest first.

   Emit only non-empty entries (§2.3).
3. GraphQL: `myWorkAttention(beaconIds)` with the ≤ 500 guard (copy `query_attention.dart:44-50`); type `MyWorkBeaconAttention` in `custom_types.dart`.
4. Update the port fakes (`attention_graphql_test.dart:19`, `legacy_canonical_compat_fixture_test.dart:124`).
5. pg tests:
   - two obligations and three news on one Beacon → correct counts and ordering;
   - a seen-but-unsettled obligation is listed;
   - a Beacon ∉ `R` is omitted even if requested;
   - an unauthorized receipt is not counted;
   - the empty result is `[]`.

**Verify:**

```bash
cd packages/server && dart run build_runner build -d
cd packages/server && dart test -t pg -j 1 test/data/repository/my_work_attention_pg_test.dart
cd packages/server && dart test test/api/controllers/graphql/attention_graphql_test.dart
./scripts/check-custom-lints.sh packages/server
```

**Acceptance:** My Work can fetch everything its cards need in one round trip.

---

## UNIT 06 — Hasura: `inbox_item` aggregations

Implements S5 (server half).

**Owns:**

```text
hasura/metadata.json   edit
```

1. In the `inbox_item` table entry, role `user` select permission: add `"allow_aggregations": true`. Do not touch `columns`, `computed_fields` or `filter`.
2. Apply with `./scripts/hasura_apply_metadata.sh`.
3. Probe as a QA user (local stack runbook): `inbox_item_aggregate(where: {status: {_eq: 0}, beacon: {can_read_content: {_eq: true}}}) { aggregate { count } }` returns a number. Record the probe and its result in the journal.

**Verify:**

```bash
./scripts/hasura_apply_metadata.sh
python3 -c "import json;m=json.load(open('hasura/metadata.json'));print('ok')"
```

**Acceptance:** the aggregate is readable under the same row filter; no other permission changed (`git diff hasura/metadata.json` shows one added key).

---

## UNIT 07 — Client: schema refresh and attention data layer

**Owns:**

```text
packages/client/lib/data/gql/schema.graphql                                         regenerated
packages/client/lib/features/attention/data/gql/attention_feed.graphql              edit
packages/client/lib/features/attention/data/gql/attention_mark_all_seen.graphql     edit
packages/client/lib/features/attention/data/gql/attention_surface_summary.graphql   new
packages/client/lib/features/attention/data/gql/attention_mark_seen_for_beacon.graphql  new
packages/client/lib/features/attention/data/gql/my_work_attention.graphql           new
packages/client/lib/domain/attention/entity/attention_feed.dart                     edit
packages/client/lib/domain/attention/entity/attention_receipt.dart                  edit
packages/client/lib/domain/attention/entity/attention_summary.dart                  edit
packages/client/lib/domain/attention/entity/my_work_beacon_attention.dart           new
packages/client/lib/domain/attention/port/attention_repository_port.dart            edit
packages/client/lib/data/repository/attention_repository.dart                       edit
packages/client/test/**                                                             fakes (see 4)
```

1. Refresh the SDL (§3 rule 5), then add and extend the documents. `attention_feed.graphql` selects `surface itemKind forwardOutcome forwardCount digestCount` and takes `$surface: String`.
2. Entities:
   - `AttentionSurface` and `AttentionItemKind` enums (§2.5);
   - `AttentionReceipt` gains `surface`, `itemKind`, `forwardOutcome` (an enum `AttentionForwardOutcome` mirroring the wire values), `forwardCount`, `digestCount`;
   - `AttentionSurfaceSummary`;
   - `MyWorkBeaconAttention`.
3. Port (`attention_repository_port.dart:3-23`):
   - `fetch` gains `AttentionSurface? surface`;
   - `markAllSeen({AttentionSurface? surface})`;
   - new `surfaceSummary()`, `markSeenForBeacon(String beaconId)`, `myWorkAttention(Set<String> beaconIds)`.

   Implement them in the Ferry adapter (`data/repository/attention_repository.dart:29-80`); map unknown wire values to a safe default (`receipt` / `activity`) and log them.
4. **Update every fake implementing `AttentionRepositoryPort`.** Find them with `grep -rn "implements AttentionRepositoryPort" packages/client/test packages/client/integration_test`. The previous plan counted ten, e.g. `test/domain/attention/attention_case_test.dart:30-87`, `test/features/home/home_attention_cubit_test.dart:28`, `test/features/updates/updates_feed_cubit_test.dart:29`. A missed fake stops the analyzer for the whole package.
5. Unit tests: mapping of every new field and enum; an unknown `itemKind` maps to `receipt`; error propagation — an unavailable summary is distinguishable from zero.

**Verify:**

```bash
cd packages/client && dart run build_runner build -d
cd packages/client && flutter test test/domain/attention/ test/data/gql/direct_v2_schema_overlay_test.dart
cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** the client can read feeds per surface, the surface summary and per-Request attention, and can mark seen by Request.

---

## UNIT 08 — Client: `AttentionCase` surfaces, summary and invalidation

Implements S4 and C2.

**Owns:**

```text
packages/client/lib/domain/attention/attention_case.dart          edit
packages/client/lib/domain/attention/entity/attention_feed.dart   edit
packages/client/test/domain/attention/attention_case_test.dart    edit
packages/client/test/domain/attention/attention_surfaces_test.dart  new
```

1. Add the destination ids of §2.5 and a pure `AttentionSurface? surfaceForDestination(String id)`:
   - `activityStream` → `activity`;
   - `history` → null;
   - `activity` (legacy) → null;
   - `myWorkObligations` (legacy) → null.
2. `_requestHeadRefresh` and `fetchNextPage` (`attention_case.dart:182-208`, `:325-367`) pass the destination's surface.
3. Add `Stream<AttentionSurfaceSummary> surfaceSummary`. It is fetched independently of any mounted feed:
   - on account change;
   - on `RealtimeEntityKind.notification`, `helpOffer` and `inboxItem` changes;
   - on catch-up and block changes (`:111-118`);
   - after every ack.

   **Scope changes arrive as `helpOffer` / `inboxItem` / block events.** On any of them, also request a head refresh of attached `activityStream` destinations: an offer-help moves Beacons between surfaces.
4. Add `markSeenForBeacon(beaconId)` and `markAllSeen({surface})`. Optimistic unread adjustment uses `receipt.surface`; always reconcile by refetching the surface summary (`_applyOptimisticAcks`, `:459-485`).
5. Keep `unreadSummary` and `snapshot.summary` for the legacy UI until UNIT 21.
6. Tests:
   - the destination → surface map;
   - summary refresh on each trigger;
   - an offer-help event refreshes `activityStream`;
   - round trip `activityStream` → `history` → `activityStream` keeps view, search and scroll state (arch §7);
   - a stale-generation response is ignored.

**Verify:**

```bash
cd packages/client && flutter test test/domain/attention/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** any widget can mount a surface-scoped feed, and the home shell can read both surface totals without mounting a feed.

---

## UNIT 09 — Client: redesign gate and design-system components

Implements C1.

**Owns:**

```text
packages/client/lib/features/home/domain/work_activity_redesign_gate.dart            new
packages/client/lib/design_system/components/tentura_section_header.dart            new
packages/client/lib/design_system/components/tentura_attention_summary_row.dart     new
packages/client/lib/design_system/tentura_design_system.dart                        edit (barrel export)
packages/client/lib/features/inbox/ui/widget/inbox_triage_row.dart                  edit
packages/client/lib/features/updates/ui/widget/updates_feed_pane.dart               edit
packages/client/test/design_system/tentura_section_header_golden_test.dart          new
packages/client/test/design_system/tentura_attention_summary_row_golden_test.dart   new
```

1. **Gate**: copy the `my_work_obligations_gate.dart` pattern with default `false`, then run build_runner (Injectable).
2. **`TenturaSectionHeader`**:
   - required `label`, optional `count` (`· N`), optional `helperText`, optional `semanticsIdentifier`;
   - label in `TenturaText.typeLabel` caps; helper in `TenturaText.bodySmall(tt.textMuted)`; spacing from `tt.sectionGap` / `tt.tightGap`;
   - `Semantics(header: true)`.
3. **`TenturaAttentionSummaryRow`**:
   - lifted from the near-identical `InboxTriageRow` body (`inbox_triage_row.dart:56-95`) and `_CollapsedInvitePromptRow` (`updates_feed_pane.dart:491-514`);
   - optional leading widget (avatars / glyph), label (≤ 2 lines), trailing chevron, `onTap`, `semanticsLabel`, test id;
   - tokens only.
4. Re-point both existing rows at the new component. **No visual change**: goldens of the old rows, if any, must not move beyond token snapping.
5. Goldens for both components: light/dark × en/ru × compact 360 and 390, plus a 1.3× text-scale variant.

**Verify:**

```bash
cd packages/client && dart run build_runner build -d
cd packages/client && flutter test test/design_system/ test/features/inbox/inbox_triage_row_test.dart
./scripts/check-custom-lints.sh packages/client
cd packages/tentura_lints && dart test
```

**Acceptance:** both components exist with goldens; the gate exists and is off; no user-visible change.

---

## UNIT 10 — Client: history row polish (ungated)

Implements design §7.4. The **only** pre-flip unit allowed to change existing surfaces.

**Owns:**

```text
packages/client/lib/features/updates/ui/widget/updates_feed_tile.dart     edit
packages/client/lib/features/updates/ui/widget/updates_day_groups.dart    edit
packages/client/lib/features/updates/updates_receipt_display_copy.dart    edit (only if headline/subject needs it)
packages/client/test/features/updates/updates_feed_tile_golden_test.dart  edit (goldens under test/features/updates/goldens/)
packages/client/test/features/updates/updates_day_groups_test.dart        new
```

1. Glyphs (`updatesFeedGlyphFor`, `updates_feed_tile.dart:18-65`): add `request_status_changed`, `offer_accepted`, `mutual_connection_formed`, trust up/down (already partly mapped) and a forward glyph (`TenturaIcons.send` or the closest existing `TenturaIcons` member; do not add raw `Icons.*` if a `TenturaIcons` fits).
2. **Remove the trailing seen toggle** (`radio_button_unchecked` / `check_circle`, `:128-137`).
   - Unread = the existing leading dot + a heavier title weight.
   - Mark seen / unseen moves to:
     - a row overflow;
     - secondary tap;
     - a hover toolbar on pointer devices, filtered by `PointerDeviceKind.mouse`. Follow the pattern in `lib/features/beacon_threads/ui/widget/room_message_tile.dart`.
   - Never long-press alone. All targets 48dp.
3. Day headers (`updates_day_groups.dart:72-84`): today / yesterday stay; otherwise locale `DateFormat.MMMd`, and `yMMMd` when the year differs. Not `dateFormatYMD`.
4. Headline = the event, supporting line = the subject (Request title), for every presentation key in `updates_receipt_display_copy.dart`. Where a key currently uses the Beacon slug as headline, swap.

**Verify:**

```bash
cd packages/client && flutter test test/features/updates/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** rows read as described in §7.4 on every surface that uses them; goldens updated and eyeballed.

---

## UNIT 11 — Client: My Work attention state

Implements design §4.2–4.3 (data only).

**Owns:**

```text
packages/client/lib/features/my_work/ui/bloc/my_work_state.dart       edit
packages/client/lib/features/my_work/ui/bloc/my_work_cubit.dart       edit
packages/client/lib/features/my_work/domain/use_case/my_work_case.dart  edit
packages/client/test/features/my_work/my_work_attention_state_test.dart  new
```

1. Add `Map<String, MyWorkBeaconAttention> attentionByBeacon` (default empty) and `bool attentionLoaded` to `MyWorkState`. Keep it **outside** the card view models: `derive_my_work_cards.dart` stays untouched.
2. After `loadDeskInit` + `loadReviewWindows` (`my_work_cubit.dart:205-217`), when the gate is on, fetch `myWorkAttention` for the union of non-archived and archived card ids, chunked at 500. Stale-sequence guard as for cards (`_fetchSeq`).
3. The existing `notification` realtime refresh (`:62-69`) already covers updates; add nothing there. A failed attention fetch keeps cards and marks attention unknown. Do not render it as zero (arch §4.8).
4. `Future<void> openedBeacon(String beaconId)` on the cubit calls `AttentionCase.markSeenForBeacon` and optimistically zeroes `unseenCount` for that Beacon; obligations stay.
5. Tests: gate off → no attention fetch; gate on → the map is populated; the stale response is dropped; failure → cards remain, `attentionLoaded == false`; `openedBeacon` zeroes unseen and keeps obligations.

**Verify:**

```bash
cd packages/client && dart run build_runner build -d
cd packages/client && flutter test test/features/my_work/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** the cubit exposes per-Request attention behind the gate. No visible change.

---

## UNIT 12 — Client: My Work obligation block and what's-new row

**Owns:**

```text
packages/client/lib/features/my_work/ui/widget/my_work_obligation_block.dart   new
packages/client/lib/features/my_work/ui/widget/my_work_whats_new_row.dart      new
packages/client/lib/features/my_work/ui/widget/my_work_cards.dart              edit
packages/client/lib/features/my_work/ui/widget/my_work_last_event_row.dart     edit
packages/client/l10n/app_en.arb                                                edit
packages/client/l10n/app_ru.arb                                                edit
packages/client/test/features/my_work/my_work_obligation_block_golden_test.dart  new
packages/client/test/features/my_work/my_work_whats_new_row_test.dart            new
```

1. **`MyWorkObligationBlock`**:
   - one line per live obligation: actor, copy from `resolveUpdatesFeedRowCopy`, relative age, trailing `TenturaTextAction` «Готово» → `AttentionCase.settle`;
   - more than 3 lines collapse to `myWorkObligationMore` and expand in place;
   - the card's existing primary CTA (`showReviewHelpOffersCta` / `showReviewCta`, see `_openBeaconReviewHelpOffers` and `_openReviewContributions` in `my_work_cards.dart`) renders beneath as `FilledButton.tonal`;
   - test ids `my_work.obligation.$receiptId`.
2. **`MyWorkWhatsNewRow`** fills one slot:
   - with `unseenCount > 0`, `myWorkWhatsNew(count, headline)` in emphasis;
   - otherwise the existing last-event row (`my_work_last_event_row.dart`), muted.

   Test id `my_work.whats_new.$beaconId`.
3. In `my_work_cards.dart`, **under the gate only**:
   - mount both widgets on every card kind, reading `attentionByBeacon` via `BlocSelector`;
   - replace the `attentionMarked` "• New" marker with the what's-new row;
   - `_openBeacon` / `_openBeaconOrSelect` (`:125-150`) call `cubit.openedBeacon(id)`.

   With the gate off, the file behaves exactly as today.
4. Add the l10n keys `myWorkObligationDone`, `myWorkObligationMore` and `myWorkWhatsNew` (§2.6); run `flutter gen-l10n`.
5. Goldens: 0, 1, 3 and 5 obligations; what's-new on and off; light/dark, en/ru, 360, 1.3×.

**Verify:**

```bash
cd packages/client && flutter gen-l10n
cd packages/client && flutter test test/features/my_work/
./scripts/check-custom-lints.sh packages/client
bash scripts/check-user-facing-terminology.sh
```

**Acceptance:** with the gate on, cards carry their obligations and news; gate off is unchanged.

---

## UNIT 13 — Client: My Work sectioned body

Implements design §4.1, §4.4–4.6.

**Owns:**

```text
packages/client/lib/features/my_work/domain/derive_my_work_sections.dart   new
packages/client/lib/features/my_work/ui/screen/my_work_screen.dart         edit
packages/client/l10n/app_en.arb                                            edit
packages/client/l10n/app_ru.arb                                            edit
packages/client/test/features/my_work/derive_my_work_sections_test.dart   new
packages/client/test/features/my_work/my_work_sectioned_body_test.dart    new
```

1. **`deriveMyWorkSections(cards, attentionByBeacon, filter)`** → ordered `(section, cards)`. Pure and unit-tested.
   - Needs you = cards with ≥ 1 live obligation.
   - In progress = active kinds without one.
   - Finished = `isFinishedCard` without one.
   - A card appears in exactly one section. Order within a section follows the existing `compareMyWorkCardsForSort` (`derive_my_work_cards.dart:314-328`).
   - Sections apply to filters `active`, `all`, `authored` and `helpOffered`; `drafts` and `archived` return one unlabeled section.
   - The Needs you count is the number of live obligation **receipts** (D4).
2. **Under the gate**, `_MyWorkBody` (`my_work_screen.dart:315-395`) renders one `CustomScrollView`:
   - a `TenturaSectionHeader` per non-empty section, then that section's cards;
   - the Finished header's helper text is `myWorkFinishedHint`;
   - **not mounted:** `MyWorkObligationsPane`, the 2:3 `Column` (`:377-389`) and `MyWorkFinishedArchiveHint` (`:533-537`).
3. **Under the gate**, remove `_MyWorkOverflowMenu` from both the compact row and the actions (`my_work_screen.dart:61`, `:99`, `:111`). Archive stays in the filter.
4. Empty states (`:445-523`) are unchanged: no obligations → no section; no cards → orientation / empty body.
5. Add the `myWorkSection*` keys; run `flutter gen-l10n`.
6. Widget tests at 360×640 and 1.3×:
   - section order and counts;
   - with 0 obligations no Needs you header exists;
   - **the first card is fully visible on first paint**;
   - the Needs you count equals the sum of obligation lines;
   - gate off renders the legacy tree (the obligations pane is present).

**Verify:**

```bash
cd packages/client && flutter gen-l10n
cd packages/client && flutter test test/features/my_work/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** with the gate on, My Work is one scroll of Request cards in sections, with no receipt rows.

---

## UNIT 14 — Client: Activity offers cubit (paged pinned zone)

Implements design §5.1 and §5.6 (source 1).

**Owns:**

```text
packages/client/lib/features/inbox/data/gql/inbox_fetch.graphql                 edit (extract fragment)
packages/client/lib/features/inbox/data/gql/activity_offers.graphql             new
packages/client/lib/features/inbox/data/repository/inbox_repository.dart        edit
packages/client/lib/features/inbox/domain/use_case/inbox_case.dart              edit
packages/client/lib/features/inbox/ui/bloc/activity_offers_cubit.dart           new
packages/client/lib/features/inbox/ui/bloc/activity_offers_state.dart           new
packages/client/test/features/inbox/activity_offers_cubit_test.dart             new
```

1. Extract `fragment InboxItemFields on inbox_item` from `inbox_fetch.graphql:8-26` and use it in `InboxFetch`. The generated mapping stays identical.
2. `activity_offers.graphql` holds one document for all pages:
   - `where: {status: {_eq: 0}, beacon: {can_read_content: {_eq: true}}, _or: [{latest_forward_at: {_lt: $at}}, {latest_forward_at: {_eq: $at}, beacon_id: {_lt: $id}}]}`, `order_by: [{latest_forward_at: desc}, {beacon_id: desc}]`, `limit: $limit`;
   - the first page passes the sentinel `$at = "9999-12-31T00:00:00Z"`, `$id = ""`;
   - plus `inbox_item_aggregate` with the same `where` minus the keyset, for the header count.

   Reuse the existing `InboxItem` mapping (`inbox_repository.dart:40-60`).
3. `ActivityOffersCubit` state: `items`, `totalCount`, `hasMore`, `loadingMore`, `heldBackIds` (live arrivals while scrolled away), `unseenBeaconIds`, error flags per source.
   - `loadFirst()`, `loadMore()` (page 20), `revealHeldBack()`.
   - `setScrolledAway(bool)`: when true, new arrivals go to `heldBackIds`, not `items`.
4. **Live changes.** Subscribe to `InboxCase.deskRelevantChanges` and `helpOfferChanges` (`inbox_case.dart:48-73`). For the changed Beacon, refetch its row with a single-row variant of the same query.
   - Still open → upsert: insert at the top when not scrolled away, otherwise hold back.
   - No longer open → remove and emit a `Demoted(beaconId)` effect for UNIT 17.
   - Refresh `totalCount` on every change.
5. Unseen dots come from `AttentionCase.unreadForBeacons` over the loaded ids, in the same chunking style as `home_attention_cubit.dart:156-190`.
6. Tests:
   - paging with ties on `latest_forward_at`;
   - live insert at top versus held back;
   - demotion on watch / reject / help / forward;
   - restore-rejected re-inserts;
   - the count stays correct before all pages load;
   - a failed count never renders as zero.

**Verify:**

```bash
cd packages/client && dart run build_runner build -d
cd packages/client && flutter test test/features/inbox/activity_offers_cubit_test.dart
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** open forwards are paged, counted and kept live. `InboxCubit` is untouched: it still feeds Watching (N), the Rejected route and the legacy UI.

---

## UNIT 15 — Client: offer card, forward row, digest row

Implements design §5.1–5.3 anatomy.

**Owns:**

```text
packages/client/lib/features/inbox/ui/widget/inbox_card_actions.dart          new (moved helpers)
packages/client/lib/features/inbox/ui/widget/inbox_triage_list.dart           edit (re-export or import moved helpers)
packages/client/lib/features/inbox/ui/screen/inbox_watching_screen.dart       edit (imports)
packages/client/lib/features/inbox/ui/widget/activity_offer_card.dart         new
packages/client/lib/features/inbox/ui/widget/activity_forward_row.dart        new
packages/client/lib/features/inbox/ui/widget/activity_watching_digest_row.dart  new
packages/client/l10n/app_en.arb                                               edit
packages/client/l10n/app_ru.arb                                               edit
packages/client/test/features/inbox/activity_offer_card_golden_test.dart      new
packages/client/test/features/inbox/activity_forward_row_test.dart            new
```

1. **Move without behaviour change** `inboxOfferHelp`, `inboxForwardItem` and `inboxCardAllowsOfferHelp` (`inbox_triage_list.dart:222-283`, used by `inbox_watching_screen.dart:155,173-174`) into `inbox_card_actions.dart`. Commit this move on its own.
2. **`ActivityOfferCard`** — bounded (design §5.1), with two variants.
   - **Forward** (`InboxItem`):
     - avatar of the latest forwarder, headline = Request title (≤ 2 lines), why-line «переслал(а) X, +N» (1 line), age, unseen dot;
     - `FilledButton.tonal` «Помочь» (when `inboxCardAllowsOfferHelp`), text actions «Переслать» and «Наблюдать», header ✕ → `showInboxDismissDialog` + `reject`;
     - handlers reuse `inbox_card_actions.dart` and the existing dialogs (`inbox_triage_list.dart:158-172`);
     - tap on the body opens the Request and calls `AttentionCase.markSeenForBeacon`.
   - **Prompt** wraps `InviteAcceptedReceiptCard` behaviour (`invite_accepted_receipt_card.dart`) in the same anatomy; the setup sheet stays.
   - Test id `activity-offer-$beaconId` (prompt: `activity-prompt-pin-$receiptId`, existing).
3. **`ActivityForwardRow`** for `itemKind == forward`:
   - glyph, «Title — переслал(а) X», the outcome label (§2.6) and age;
   - `notInterested` shows «Вернуть» → `InboxCubit.unreject`; `closedBeforeResponse` / `deletedBeforeResponse` show «Скрыть» → `dismissTombstone`;
   - tap opens the Request (`helping` lands on the Request, which now lives in My Work).
   - Test id `activity-forward-row-$beaconId`.
4. **`ActivityWatchingDigestRow`** is a `TenturaAttentionSummaryRow` with `activityWatchingDigest(count)`; tap opens `InboxWatchingRoute`. Test id `activity-watching-digest`.
5. Add the `activityForwardOutcome*`, `activityForwardRestore` and `activityWatchingDigest` keys; run `flutter gen-l10n`.
6. Goldens: forward card with and without offer-help, prompt card, each forward-row outcome; light/dark, en/ru, 360, 1.3×. **Assert the forward card height stays ≤ 180 logical px at 1.3×.**

**Verify:**

```bash
cd packages/client && flutter gen-l10n
cd packages/client && flutter test test/features/inbox/
./scripts/check-custom-lints.sh packages/client
bash scripts/check-user-facing-terminology.sh
```

**Acceptance:** the three widgets exist with goldens; nothing mounts them yet.

---

## UNIT 16 — Client: Activity stream view

Implements design §5, §5.2, §5.6.

**Owns:**

```text
packages/client/lib/features/inbox/ui/widget/activity_stream_view.dart   new
packages/client/lib/features/inbox/ui/screen/inbox_screen.dart           edit
packages/client/lib/features/updates/ui/bloc/updates_feed_cubit.dart    edit (destination param only, if needed)
packages/client/l10n/app_en.arb                                          edit
packages/client/l10n/app_ru.arb                                          edit
packages/client/test/features/inbox/activity_stream_view_test.dart      new
```

1. `ActivityStreamView` is one `CustomScrollView`.
   - **Pinned zone** comes first:
     - a `TenturaSectionHeader` «Для вас · N» (`totalCount`, test id `activity-for-you-header`);
     - then fresh pending prompts per arch §5 (≤ 2 pinned, ≥ 3 → one collapsed row opening `PromptBatchSheet`). Reuse `computeInvitePromptPinPlacement` (`updates_feed_pane.dart:527-557`) over the loaded stream items;
     - then `ActivityOfferCard`s from `ActivityOffersCubit`, with a bottom progress row until `hasMore == false`.
   - **Then the stream**: an `UpdatesFeedCubit(destinationId: activityStream)`, day-grouped (`flattenUpdatesFeed`). Each item renders by `itemKind`: `receipt` → `UpdatesFeedTile`; `forward` → `ActivityForwardRow`; `watchingDigest` → `ActivityWatchingDigestRow`.
   - Receipts lifted into the pinned zone are removed from the stream, as today (`updates_feed_pane.dart:232-234`).
2. **Load-more** is a single scroll listener. It triggers the pinned source first; once `hasMore == false`, it triggers the stream's `loadNextPage` (threshold `tt.sectionGap`, as `updates_feed_pane.dart:94-101`). `RefreshIndicator` refreshes both sources.
3. **Under the gate**, `_inboxActivityFeedBody` (`inbox_screen.dart:217-243`) returns `ActivityStreamView`; the legacy body (triage row + `UpdatesFeedPane`) stays for gate off. Keep the keep-alive / `PageStorageKey` wrapper (`:193-215`).
4. Per-source loading and failure (arch §4.8): a failed pinned source shows an inline retry row and never blocks the stream, and vice versa.
5. Widget tests with fake sources:
   - order is pinned header → prompts → offers → stream;
   - the stream starts only after the pinned zone is exhausted;
   - the three item kinds render;
   - **360×640 @1.3×: the first offer card is fully visible**;
   - 60 offers + 120 stream items scroll to the end with no duplicates;
   - gate off renders the legacy body.

**Verify:**

```bash
cd packages/client && flutter gen-l10n
cd packages/client && flutter test test/features/inbox/ test/features/updates/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** with the gate on, Activity is the design's single stream.

---

## UNIT 17 — Client: live arrival and demotion motion

Implements design §5.1 (Motion) and §5.6 (live arrival).

**Owns:**

```text
packages/client/lib/features/inbox/ui/widget/activity_stream_view.dart   edit
packages/client/lib/features/inbox/ui/bloc/activity_offers_cubit.dart    edit
packages/client/l10n/app_en.arb                                          edit
packages/client/l10n/app_ru.arb                                          edit
packages/client/test/features/inbox/activity_live_motion_test.dart      new
```

1. Report "scrolled away" to the cubit when the offset exceeds one card height.
   - Held-back arrivals show a pill `activityNewItemsPill(count)` ↑ (test id `activity-new-items-pill`), anchored below the app bar.
   - Tapping it scrolls to top and calls `revealHeldBack()`.
   - Visible content must not shift.
2. **Demotion**. On `Demoted(beaconId)`, collapse the card out (`SizeTransition` + fade, 200–250 ms, `MediaQuery.disableAnimations` → instant) and head-refresh the stream.
   - If the matching `inbox:<beaconId>` row lands inside the currently visible range, insert it there with the same transition.
   - Otherwise show a SnackBar `activityMovedToStream` with the action `activityShowInStream`, which scrolls to the row, loading pages until it is found (bounded by `hasNextPage`).
   - Reuse the `pendingMovedNudge` SnackBar plumbing pattern (`inbox_screen.dart:73-94`).
3. Items closed on another device demote the same way wherever they are loaded.
4. Tests:
   - arrival at offset 0 inserts in place;
   - arrival while scrolled away shows the pill and moves no widget (compare global positions before and after);
   - watch → demotion → forward row appears with outcome «Вы наблюдаете»;
   - with reduced motion, no animation runs;
   - «Показать» scrolls to the row.

**Verify:**

```bash
cd packages/client && flutter gen-l10n
cd packages/client && flutter test test/features/inbox/activity_live_motion_test.dart
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** acceptance items 7 and 9 of the design plan §9 hold in widget tests.

---

## UNIT 18 — Client: Activity chrome and notification history route

Implements design §5.4 and §6.

**Owns:**

```text
packages/client/lib/features/inbox/ui/screen/inbox_screen.dart         edit
packages/client/lib/features/updates/ui/screen/updates_screen.dart     edit
packages/client/lib/app/router/root_router.dart                        edit
packages/client/lib/consts.dart                                        edit
packages/client/l10n/app_en.arb                                        edit
packages/client/l10n/app_ru.arb                                        edit
packages/client/test/features/inbox/activity_chrome_test.dart          new
packages/client/test/features/updates/notification_history_screen_test.dart  new
```

1. **Under the gate**, the Activity top bar (`inbox_screen.dart:103-120`) shows:
   - the title from `l10n.inbox` («Активность»), not `updatesTitle`;
   - an `IconButton` `Icons.done_all` (tooltip `updatesMarkAllSeen`) → `AttentionCase.markAllSeen(surface: activity)`, disabled when `activityUnreadTotal == 0`;
   - `_InboxOverflowMenu` (`:245-284`) gains «История уведомлений» → `UpdatesRoute`.

   There are no view tabs and no search on the gated body.
2. **History screen**:
   - add `kPathInboxHistory` and register `UpdatesRoute` at it next to the Watching / Rejected routes (`root_router.dart:171-183`);
   - `UpdatesScreen` gets a `TenturaTopBar` with back and the title `notificationHistoryTitle`;
   - its cubit uses `AttentionFeedDestinationId.history`; `UpdatesFeedPane` keeps All / Unread, search, day groups and settle.

   The `kPathUpdates` redirect changes only in UNIT 20.
3. Run the AutoRoute build_runner; add `notificationHistoryTitle`; run `flutter gen-l10n`.
4. Tests:
   - gated chrome: title, mark-all scoped to activity, overflow entries;
   - the history screen lists receipts of **both** surfaces with search working;
   - back returns to Activity with its scroll restored.

**Verify:**

```bash
cd packages/client && dart run build_runner build -d
cd packages/client && flutter gen-l10n
cd packages/client && flutter test test/features/inbox/activity_chrome_test.dart test/features/updates/notification_history_screen_test.dart
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** Activity chrome matches design §5.4 behind the gate; the history screen is reachable from the overflow.

---

## UNIT 19 — Client: nav indicators and surface-aware open

Implements C6 and C7.

**Owns:**

```text
packages/client/lib/features/home/ui/bloc/home_attention_state.dart     edit
packages/client/lib/features/home/ui/bloc/home_attention_cubit.dart     edit
packages/client/lib/features/home/ui/widget/inbox_navbar_item.dart      edit
packages/client/lib/features/home/ui/widget/my_work_navbar_item.dart    edit
packages/client/lib/app/router/root_router.dart                         edit
packages/client/test/features/home/home_attention_cubit_test.dart       edit
packages/client/test/features/home/my_work_navbar_item_test.dart        edit
packages/client/test/features/home/work_activity_nav_indicators_test.dart  new
```

1. `HomeAttentionState` gains `activityUnreadTotal`, `myWorkUnreadTotal` and `surfaceSummaryLoaded`, fed by `AttentionCase.surfaceSummary` (UNIT 08). **Under the gate:**
   - **Activity** = dot only when `activityUnreadTotal > 0` and Activity is not the active tab. No number, ever (D5).
   - **My Work** = number `needsYouTotal` when > 0 (visible on the active tab too, as today, `home_attention_state.dart:66-70`); else a dot when `myWorkUnreadTotal > 0` and My Work is not the active tab.
   - Accessible descriptions differ: "N obligations" versus "new activity".

   Gate off keeps `showInboxTriageBadge` / `showInboxUnreadDot` / `showMyWorkObligationBadge` as they are.
2. **`openFromUpdate`** (`root_router.dart:589-593`), under the gate, picks the underlying branch by `receipt.surface`: `myWork` → the Work branch, `activity` → the Activity branch. It replaces `preferUpdatesBranch: true`.

   OS push opens (`lifecycle_handler_native.dart:62-68`) are unchanged: the push payload carries only `link` + `beaconId` (`fcm_service.dart:196-207`), and no push payload change is part of this plan.
3. Tests:
   - indicator matrix: gate on/off × obligations 0/3 × unread per surface × active tab;
   - an `invite_accepted` receipt lights the Activity dot. This is the arch §1.1 coverage fix;
   - a Beacon-scoped My Work receipt lights only My Work;
   - `openFromUpdate` picks the branch per surface.

**Verify:**

```bash
cd packages/client && flutter test test/features/home/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** indicators follow D4/D5 behind the gate.

---

## UNIT 20 — Flip the gate, redirects, e2e helpers, first-paint proofs

**Owns:**

```text
packages/client/lib/features/home/domain/work_activity_redesign_gate.dart   edit (default true)
packages/client/lib/app/router/root_router.dart                            edit
packages/client/integration_test/support/e2e_test_helpers.dart             edit
packages/client/integration_test/*.dart                                    edit where they reach triage
packages/client/test/**                                                    edit (tests that assumed gate off)
packages/client/test/features/home/work_activity_first_paint_test.dart     new
```

1. Default the gate to `true`; run build_runner.
2. Redirect `kPathUpdates` → `kPathInboxHistory` (`root_router.dart:185-188`). `kPathNotifications` → `kPathUpdates` chains unchanged.
3. **e2e helpers.** `goToInboxTriage` (`e2e_test_helpers.dart:616-619`) navigates to `kPathInbox` and finds the offer card by `activity-offer-$beaconId`. Update `offerHelpFromInbox` (`:621`) and `openRequestFromInbox` (`:666`) accordingly.
4. Tests that asserted the legacy tree **with the gate implicitly off**: set the gate explicitly to `false` where they test legacy code still present until UNIT 21, or move them to the new expectations. Record each in the journal under rule 8.
5. `work_activity_first_paint_test.dart`: the full home shell at 360×640 and 1.3× with fixtures.
   - My Work: the first card is fully visible, and nothing fixed sits below the app bar.
   - Activity: the first offer card is fully visible.
   - Both tabs: no receipt row on My Work; no receipt about an in-scope Beacon on Activity (design §9.1).
6. Run the web e2e suite locally (`./scripts/run_client_integration_web_local.sh`), at least `request_lifecycle_create_forward_inbox_test.dart`, `request_lifecycle_offer_admit_chat_test.dart`, `request_lifecycle_closed_to_archive_test.dart` and `tab_attention_forced_background_test.dart`. Record the results.

**Verify:**

```bash
cd packages/client && dart run build_runner build -d
cd packages/client && flutter test
./scripts/check-custom-lints.sh packages/client
./scripts/run_client_integration_web_local.sh
```

**Acceptance:** design §9 items 1–9 hold with the gate on by default; the full client test suite is green.

---

## UNIT 21 — Cleanup: legacy paths, both gates, triage route

Implements D11 and the design §8.3 blast radius.

**Owns (delete unless marked):**

```text
packages/client/lib/features/my_work/ui/widget/my_work_obligations_pane.dart        delete
packages/client/lib/features/my_work/ui/widget/my_work_finished_status_row.dart     delete
packages/client/lib/features/my_work/domain/my_work_obligations_gate.dart           delete
packages/client/lib/features/home/domain/work_activity_redesign_gate.dart           delete
packages/client/lib/features/inbox/ui/widget/inbox_triage_row.dart                 delete
packages/client/lib/features/inbox/ui/widget/inbox_triage_list.dart                 delete
packages/client/lib/features/inbox/ui/screen/inbox_triage_screen.dart              delete
packages/client/lib/features/inbox/ui/widget/inbox_tombstone_section.dart           delete
packages/client/lib/features/inbox/ui/widget/inbox_tombstone_card.dart              delete if unused
packages/client/lib/features/inbox/domain/enum.dart                                 edit (remove InboxSort)
packages/client/lib/features/inbox/ui/bloc/inbox_cubit.dart, inbox_state.dart       edit (remove sort, tombstonesLast24h if unused)
packages/client/lib/features/my_work/ui/bloc/*                                      edit (remove finishedArchiveHintDismissed)
packages/client/lib/features/my_work/domain/use_case/my_work_case.dart              edit (obligation gate always on)
packages/client/lib/features/inbox/ui/screen/inbox_screen.dart                      edit (legacy body out)
packages/client/lib/features/my_work/ui/screen/my_work_screen.dart                  edit (legacy body out)
packages/client/lib/domain/attention/entity/attention_feed.dart                     edit (drop myWorkObligations, legacy activity ids)
packages/client/lib/features/home/ui/bloc/home_attention_*.dart                     edit (drop triage badge fields)
packages/client/lib/app/router/root_router.dart, lib/consts.dart                    edit (kPathInboxTriage → redirect to kPathInbox)
packages/client/lib/ui/test_ids.dart                                                edit (drop activityTriageRow, myWorkObligationsPane)
packages/client/l10n/app_en.arb, app_ru.arb                                         edit (drop keys that become unused)
```

1. Delete the legacy trees and both gates, and resolve every reference.
   - `HomeTabReselectCubit`'s Activity reselect (`inbox_screen.dart:61-66`, today `setSort(InboxSort.recent)`) becomes "scroll to top".
   - `InboxCubit` stays for Watching (N), Watching and Rejected.
2. Drop l10n keys that no longer have a reference: `activityTriageRequestsNeedResponse`, `inboxTabNeedsMe` if unused, and the `inboxSort*` keys. Confirm each with grep before deleting.
3. Rewrite or delete the tests in design §8.3, plus `test/features/graph/inbox_merit_rank_sort_test.dart` and `test/features/inbox/inbox_watching_route_test.dart`, recording each under rule 8.
4. `CONTEXT.md` §My desk *Finished card*: replace "A one-time inline hint explains…" with the Finished-section helper text. Terminology only.

**Verify:**

```bash
cd packages/client && dart run build_runner build -d
cd packages/client && flutter gen-l10n
cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos
cd packages/client && flutter test
./scripts/check-custom-lints.sh packages/client
bash scripts/check-user-facing-terminology.sh
grep -rn "InboxTriageRoute\|MyWorkObligationsPane\|InboxSort\|workActivityRedesignGate\|myWorkObligationsGate" packages/client/lib packages/client/test
```

**Acceptance:** the last grep prints nothing; the suite is green; `kPathInboxTriage` redirects.

---

## UNIT 22 — Release: version, cache-buster, acceptance matrix

**Owns:**

```text
packages/client/pubspec.yaml     edit (version)
packages/client/web/index.html   edit (flutter_bootstrap.js?v=)
docs/plans/work-activity-redesign-implementation-journal.md   edit (final evidence)
```

1. Bump the patch version (`pubspec.yaml:5`, currently `7.6.4` — re-read, it may have moved) and sync `web/index.html:132` `flutter_bootstrap.js?v=<version>`. Both files may carry unrelated pre-existing edits: change only these two lines.
2. Run the full matrix:
   - server pg suites of UNITs 01–05;
   - server unit tests;
   - `flutter test`;
   - custom lints for both packages;
   - the terminology check;
   - web e2e.
3. Walk design §9 items 1–10 one by one in the journal, each with its evidence (test name or command).
4. Manual smoke on the local stack at 390×844 with a QA user that has obligations, open forwards and invites (`it-helper-mtx-1786881694-32` has 36 receipts and 8 obligations): one screenshot per tab, attached to the journal by path.

**Verify:**

```bash
cd packages/server && dart test -t pg -j 1
cd packages/server && dart test
cd packages/client && flutter test
./scripts/check-custom-lints.sh packages/client
./scripts/check-custom-lints.sh packages/server
bash scripts/check-user-facing-terminology.sh
./scripts/run_client_integration_web_local.sh
```

**Acceptance:** every design §9 item has evidence in the journal; the version and cache-buster are in sync; everything is committed; unrelated pre-existing changes are untouched.

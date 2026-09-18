---
status: ready
kind: implementation-plan
source: docs/plans/availability-request-receptiveness-architecture.md
source_revision: 3
---
# Availability / request-receptiveness — implementation plan

This is the execution plan for
[`availability-request-receptiveness-architecture.md`](availability-request-receptiveness-architecture.md)
rev 3. It is written for a literal implementation model such as Composer 2.5: every unit has
fixed ownership, prerequisites, ordered steps, tests, and a stop condition. The architecture is
normative. This plan resolves the two recommendations that rev 3 still labels open; an executor
must not make additional product choices.

## 0. Scope closures and frozen contracts

The user approved rev 3 as implementation-ready on 2026-08-13. Apply these final v1 choices:

1. **S10 — band rows:** exclude availability-paused people from the client-side capability band
   after `fetchForwardContext`; do not add a special pause line to a band row. Preserve the
   surviving band order. The server recommender remains availability-blind.
2. **S12 — entry point:** own profile only. Do not add a Settings tile.
3. **Migration:** the live tree ends at `m0147`; this plan owns `m0148`.
4. **Release:** the live client is `5.12.1`; this user-visible feature is `5.13.0`. Set the
   server minimum client version to `5.13.0` because `beaconForward` changes return type.
5. **Calendar representation:** a calendar date is a UTC-midnight `DateTime` in Dart and a SQL
   `date` in PostgreSQL. Construct it from year/month/day with `DateTime.utc`; never call
   `toLocal()` on it and never obtain it by calling `toUtc()` on a local midnight.
6. **Clock rule:** `todayUtc` means
   `DateTime.utc(now.toUtc().year, now.toUtc().month, now.toUtc().day)`.
7. **Pause rule:** paused iff `resumeOn != null && todayUtc.isBefore(resumeOn)`. On the resume
   date the user is available.
8. **Horizon:** reject `resumeOn <= todayUtc` and `resumeOn > todayUtc + 90 calendar days`.
9. **Forward result:** `beaconForward` returns `ForwardDeliveryResult!` with non-null
   `batchId`, `deliveredRecipientIds`, and `availabilitySkippedRecipientIds`.
10. **Host policy:** recipient rows receive a required enum-valued host, not an optional Boolean.
    All picker hosts show availability; the read-only lineage preview does not.
11. **Partial-copy rule:** one skipped person uses their display name. Two or more use a count;
    do not join an unbounded list of names into a snackbar or dialog.
12. **Janitor cadence:** run the non-load-bearing stale-row cleanup at most once every six hours
    from `TaskWorkerCase`.

Do not add availability to presence, WebSockets, realtime entities, Updates, notifications,
avatars, room/member lists, contacts, global search, My Work, or Inbox. Do not gate existing
forwards, chats, offers, admissions, cancellations, edits, or beacon-invite acceptance. Do not
edit generated files by hand.

## 1. Live baseline and stop conditions

At plan-writing time:

```text
latest migration                    m0147
packages/client/pubspec.yaml        5.12.1
packages/client/web/index.html      flutter_bootstrap.js?v=5.12.1
packages/server/lib/env.dart        kDefaultMinClientVersion = 5.6.38
```

Before UNIT 00, verify those values. Stop and record `BLOCKED` instead of guessing when:

- the latest migration is no longer `m0147` or `m0148` already exists;
- the client version is no longer `5.12.1`;
- an owned file has unrelated local modifications that cannot be preserved by a narrow edit;
- rev 3's field names, mutation names, temporal rule, or typed-result fields have changed;
- a required PostgreSQL/Hasura test cannot be run in an isolated disposable database.

A changed starting Git commit alone is not a blocker. Reconcile the live symbol and proceed if
the contracts and reserved identifiers above still match.

## 2. Executor contract

1. Work units in manifest order. Complete one unit, run its checks, append the journal, and make
   its focused local commit before starting the next unit. Do not push or deploy.
2. Preserve all pre-existing modified and untracked files. Never reset, stash, clean, or stage
   unrelated work. Stage explicit paths only.
3. Create
   `docs/plans/availability-request-receptiveness-implementation-journal.md` in UNIT 00. Every
   entry contains unit, status, commit, exact tests, files, findings, and remaining work.
4. If live code contradicts this plan, do not improvise across a boundary. Record the exact
   symbol/path and stop that unit. Mechanical line-number drift is not a contradiction.
5. Server use cases depend on domain ports only. Data repositories implement those ports.
   Client domain types never import data/UI. Cubits never import `data/service`.
6. Use Freezed for new client/server domain entities where the package convention applies. Run
   codegen; never edit `*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, or `_g/`.
7. UI uses `package:tentura/design_system/tentura_design_system.dart`, `context.tt`,
   `TenturaText`, `TenturaStatusText`, Material 3 buttons, and tap targets at least 48 dp. No raw
   colors, text sizes, padding numbers, or radii in feature UI. No chips/badges/icons for this
   status.
8. Tests tagged `pg` must create an isolated disposable PostgreSQL database. Never migrate,
   reset, or clean the shared `postgres` database.

Journal entry template:

```markdown
## UNIT <id> — <complete|partial|blocked> — <ISO date>
COMMITS: <hash and subject, or none>
TESTS: <exact command and outcome>
FILES: <paths>
FINDINGS: <live facts that differed from the plan, or none>
REMAINING: <specific work, or none>
```

## 3. Unit manifest

| Unit | Purpose | Depends on | Suggested commit |
|---|---|---|---|
| 00 | Journal and immutable baseline | — | `docs: start availability implementation journal` |
| 01 | Shared calendar/view model and entities | 00 | `feat: add availability domain model` |
| 02 | `m0148`, Drift table, Hasura visibility | 01 | `feat(server): add user availability storage` |
| 03 | Atomic availability repository, use case, janitor | 02 | `feat(server): add availability commands` |
| 04 | Server public-user read parity | 03 | `feat(server): expose availability in public users` |
| 05 | Three V2 availability mutations | 03 | `feat(server): add availability mutations` |
| 06 | Transactional forward gate and typed result | 03 | `feat(server): enforce availability on forwards` |
| 07 | Server PostgreSQL/concurrency/API proof | 04–06 | `test(server): prove availability invariants` |
| 08 | Client schema, date scalar, entities, read parity | 04–06 | `feat(client): map availability data` |
| 09 | Client availability command repository and Cubit | 05, 08 | `feat(client): wire availability commands` |
| 10 | Calendar presets, formatting, localization | 08 | `feat(client): add availability copy and dates` |
| 11 | Own-profile control and status | 09–10 | `feat(client): add availability profile control` |
| 12 | Other-profile and graph policy/rendering | 10 | `feat(client): gate person request actions` |
| 13 | Picker host policy, row precedence, band exclusion | 08, 10 | `feat(client): show availability in recipient picker` |
| 14 | Picker preselection, expiry refresh, typed delivery UX | 06, 08, 10, 13 | `feat(client): report actual forward delivery` |
| 15 | Deep-link person-forward gate | 06, 08, 10, 12 | `feat(client): gate person forward flow` |
| 16 | Client release gate and cache-buster | 11–15 | `chore: release availability client 5.13.0` |
| 17 | End-to-end and plan-wide closeout | 07, 16 | `test: close availability implementation` |

Units are sequential. Do not parallelize them: schema/codegen files, shared `Profile`, forward
contracts, and release files overlap.

## UNIT 00 — Journal and baseline

**Owns:** the journal only.

1. Record `git rev-parse HEAD`, branch, `git status --short`, migration tail, client version,
   web cache-buster, and minimum client version verbatim.
2. Copy the unit manifest into the journal as unchecked items.
3. Record that the architecture source is rev 3 and that this plan closes S10/S12 as in §0.
4. Do not alter or stage any pre-existing file.

**Acceptance:** journal exists and baseline values match §1.

## UNIT 01 — Shared calendar/view model and entities

**Owns:**

```text
lib/domain/enums.dart
lib/domain/availability.dart                         new
test/domain/availability_test.dart                   new
packages/client/lib/domain/entity/availability.dart  new
packages/client/lib/domain/entity/profile.dart
packages/client/test/domain/entity/availability_test.dart new
packages/server/lib/domain/entity/user_availability_entity.dart new
packages/server/test/domain/entity/user_availability_entity_test.dart new
```

1. Add `AvailabilityView { open, limited, paused }` to root `enums.dart`. No enum ordinal is a
   database or wire value.
2. In root `availability.dart`, add pure helpers:
   - `utcCalendarDate(DateTime value)` using the UTC year/month/day;
   - `isUtcCalendarDate(DateTime value)`;
   - `availabilityViewOn({bool isLimited, DateTime? resumeOn, DateTime todayUtc})` implementing
     §0.7 and asserting date-only UTC inputs in debug mode.
3. Add client `Availability` as a Freezed value object with `isLimited`, `resumeOn`,
   `Availability.open()`, `effectiveOn(todayUtc)`, and `blocksNewRequestsOn(todayUtc)`. Delegate
   the comparison to the root helper.
4. Add `@Default(Availability.open()) Availability availability` to `Profile`.
5. Add server `UserAvailabilityEntity` with `userId`, `isLimited`, `resumeOn`, and the same two
   delegated methods.
6. Cover: absent/open; limited; future pause; equality boundary; past pause; limited+future;
   limited+past fallback; UTC normalization; and no dependence on the process local timezone.
7. Run root, client, and server build runners as required by Freezed.

**Acceptance:** client and server tests execute the same root comparison; searching the new
availability files finds no `toLocal(`.

**Verify:**

```bash
dart test test/domain/availability_test.dart
(cd packages/client && dart run build_runner build -d && flutter test test/domain/entity/availability_test.dart)
(cd packages/server && dart run build_runner build -d && dart test test/domain/entity/user_availability_entity_test.dart)
```

## UNIT 02 — Storage, migration, and Hasura visibility

**Precondition:** latest migration remains `m0147`.

**Owns:**

```text
packages/server/lib/data/database/migration/m0148.dart new
packages/server/lib/data/database/migration/_migrations.dart
packages/server/lib/data/database/table/user_availability.dart new
packages/server/lib/data/database/tentura_db.dart
packages/server/test/data/database/m0148_user_availability_migration_test.dart new
packages/server/test/data/database/beacon_cover_migration_test.dart
hasura/metadata.json
```

1. Add logged `public.user_availability` exactly as architecture §5: `user_id` PK/FK cascade,
   `is_limited boolean NOT NULL DEFAULT false`, nullable `resume_on date`, unexposed
   `updated_at timestamptz`, non-empty CHECK, and partial `resume_on` index. Add no backfill and
   no user-creation trigger.
2. Add `user_availability_hidden_for_viewer(row, hasura_session)` delegating to symmetric
   `block_hides` exactly like `user_presence_hidden_for_viewer`.
3. Register `m0148` after `m0147`. Keep Drift `schemaVersion == 1`; add/register the Drift table
   and run server codegen.
4. Extend the rollback simulation so it drops `user_availability`, its function/index, and the
   `0148` schema-version row before reapplying older migrations.
5. In Hasura metadata:
   - add object relationship `user_availability` on `user` via the FK;
   - track the new table and computed field;
   - grant role `user` select only on `user_id`, `is_limited`, `resume_on`, and computed
     `hidden_for_viewer`;
   - add no insert/update/delete permission;
   - use the exact select filter `hidden_for_viewer = false AND (is_limited = true OR
     resume_on > "now()")`; Hasura emits the dynamic `now()` expression and the local
     PostgreSQL/Hasura connection must remain UTC;
   - this suppresses expired pause-only rows and retains limited rows even when their stored date
     is past. The migration/Hasura test must fail if the connection timezone makes the comparison
     differ from `(CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date`.
6. Migration tests prove logged persistence shape, CHECK, FK cascade, no per-user row/backfill,
   hidden function behavior, fresh migration, and upgrade from `m0147`.

**Acceptance:** `updated_at` is absent from Hasura permissions; expired pause-only rows are
unreadable through the relationship; `{is_limited:true,resume_on:past}` remains readable.

**Verify:**

```bash
(cd packages/server && dart run build_runner build -d)
(cd packages/server && dart test -t pg test/data/database/m0148_user_availability_migration_test.dart)
(cd packages/server && dart test -t pg test/data/database/beacon_cover_migration_test.dart)
```

## UNIT 03 — Atomic repository, use case, and janitor

**Owns:**

```text
packages/server/lib/domain/port/user_availability_repository_port.dart new
packages/server/lib/data/repository/user_availability_repository.dart new
packages/server/lib/domain/use_case/user_availability_case.dart new
packages/server/lib/domain/use_case/task_worker_case.dart
packages/server/test/domain/use_case/user_availability_case_test.dart new
packages/server/test/domain/use_case/task_worker_case_test.dart
```

1. Port methods are exactly:
   `fetchByUserIds(Set<String>)`, `setLimited(userId,isLimited)`,
   `pause(userId,resumeOn)`, `resume(userId)`, and `cleanupExpired(todayUtc)`.
2. Bind the repository to the port with Injectable. Return domain entities, never Drift rows.
3. Every mutation runs in `withMutatingUser(userId)` and takes the transaction-scoped advisory
   lock `hashtextextended('user_availability:' || userId, 4242)` before changing the row. The
   forward repository will take the same lock in UNIT 06.
4. `setLimited(true)` and `pause` use `INSERT ... ON CONFLICT` and update only their owned
   column plus `updated_at`.
5. `setLimited(false)` and `resume` use one writable CTE/statement each: update only the owned
   column, then delete iff the post-update row is `{false,null}`. Never attempt to insert that
   invalid state. Missing-row clear/resume is an idempotent success.
6. `UserAvailabilityCase` owns UTC-date validation and the 90-day horizon. Resolvers will pass a
   parsed calendar date but no resolver/repository may duplicate the horizon rule.
7. `cleanupExpired` runs as a system mutation: delete pause-only rows with
   `resume_on <= todayUtc`, then clear the date from limited rows. Add it to `TaskWorkerCase`
   behind a six-hour in-process throttle. It is hygiene only; reads must already be correct.
8. Unit-test validation, idempotency, fallback behavior, and task-worker throttling. PostgreSQL
   atomic/concurrency proof belongs to UNIT 07.

**Acceptance:** each public command is one application use-case call and one atomic repository
operation; no controller owns validation.

## UNIT 04 — Server public-user read parity

**Owns:**

```text
packages/server/lib/domain/entity/gql_public/user_availability_record.dart new
packages/server/lib/domain/entity/gql_public/user_public_record.dart
packages/server/lib/data/repository/user_profile_batch_lookup.dart
packages/server/lib/data/repository/mutual_friends_repository.dart
packages/server/lib/api/controllers/graphql/mappers/invite_genealogy_gql_maps.dart
packages/server/lib/api/controllers/graphql/mappers/gql_public_user_maps.dart
packages/server/lib/api/controllers/graphql/query/query_invite_genealogy.dart
packages/server/lib/api/controllers/graphql/query/query_invitation.dart
packages/server/lib/api/controllers/graphql/custom_types.dart
packages/server/test/api/controllers/graphql/mappers/gql_public_user_maps_test.dart
```

1. Add `UserAvailabilityRecord` and make `userAvailability` a **required** named argument on
   `UserPublicRecord`. Null relationship/open is represented by a nullable record value, not by
   omitting the constructor argument.
2. Add V2 nested `user_availability { is_limited, resume_on }` type/field. Expose a calendar-date
   string only; never `updated_at`.
3. Batch-fetch availability once in `DriftUserProfileBatchLookup.userPublicRecordsByIds`.
4. In `MutualFriendsRepository`, batch-fetch availability for all result user IDs once. Do not
   add a second per-user loop beside the existing presence lookup.
5. Pass an availability map through every invite-genealogy mapper call into `_userToPublic`.
   `QueryInviteGenealogy` obtains the batch for its returned node user IDs.
6. `QueryInvitation` obtains the issuer availability and patches `user_availability` beside its
   existing `user_presence` patch.
7. Map null/open, limited, future pause, expired pause-only, and limited+expired consistently:
   V2 producers emit `user_availability: null` for expired pause-only; they retain
   `{is_limited:true,resume_on:<past date>}` for limited+expired so the client derives limited and
   never renders the past date.
8. Add a parity test that exercises all three constructors, the serializer, invite genealogy,
   and the hand-patched invitation issuer. A missing site must fail the test or compilation.

**Acceptance:** `rg "UserPublicRecord\(" packages/server/lib` shows every constructor passing
`userAvailability:` explicitly.

## UNIT 05 — Three V2 availability mutations

**Owns:**

```text
packages/server/lib/api/controllers/graphql/input/input_field_calendar_date.dart new
packages/server/lib/api/controllers/graphql/input/_input_types.dart
packages/server/lib/api/controllers/graphql/mutation/mutation_availability.dart new
packages/server/lib/api/controllers/graphql/mutation/_mutations_all.dart
packages/server/test/api/controllers/graphql/mutation_availability_test.dart new
```

1. Add a strict ISO calendar-date input parser accepting only `YYYY-MM-DD` and constructing
   `DateTime.utc(year,month,day)`. Reject rollover strings such as `2026-02-30`. Do not use
   `InputFieldDatetime`.
2. Register exactly these non-null mutations:
   - `userAvailabilitySetLimited(isLimited: Boolean!): Boolean!`
   - `userAvailabilityPause(resumeOn: String!): Boolean!`
   - `userAvailabilityResume: Boolean!`
3. Each resolver authenticates `sub`, parses transport input, calls one
   `UserAvailabilityCase` method, and returns true. It contains no horizon, merge, or delete
   logic and no way to set another user.
4. Test through the actual GraphQL schema/document path, not by calling a resolver with a hand
   map. Cover missing/null required values, malformed dates, self-only subject, horizon edges,
   and the independence of limited/pause fields.

**Acceptance:** the former omitted-vs-null ambiguity is absent because no nullable command
argument exists.

## UNIT 06 — Transactional forward gate and typed result

**Owns:**

```text
packages/server/lib/domain/entity/forward_batch_create_result.dart new
packages/server/lib/domain/entity/forward_delivery_result.dart new
packages/server/lib/domain/port/forward_edge_repository_port.dart
packages/server/lib/data/repository/forward_edge_repository.dart
packages/server/lib/domain/use_case/forward_case.dart
packages/server/lib/api/controllers/graphql/custom_types.dart
packages/server/lib/api/controllers/graphql/mutation/mutation_forward.dart
packages/server/test/domain/use_case/forward_case_test.dart
packages/server/test/domain/use_case/forward_case_auth_test.dart
```

1. Change `createBatch` to return `ForwardBatchCreateResult(createdEdges,
   availabilitySkippedRecipientIds)`.
2. At batch start, deduplicate recipient IDs while preserving first-request order. Acquire the
   shared availability advisory locks for all unique recipients in sorted ID order to avoid
   deadlocks. Keep result lists in requested order.
3. For each recipient, use one conditional insert whose SQL predicate treats them as blocked
   when a current row has `resume_on > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date`. The
   predicate and insert run inside the existing `withMutatingUser` transaction. A skipped person
   is added only to `availabilitySkippedRecipientIds`; no edge, evidence, attribution, attention
   intent, or notification is created for them.
4. Existing active-edge dedup remains distinct from an availability skip and is not mislabeled.
5. Change `ForwardCase.forward` to return `ForwardDeliveryResult`. Propagate `createdEdges` into
   the existing evidence/attribution/attention work, and return batch ID, delivered IDs from
   actual created edges, and availability-skipped IDs from the repository.
6. Add GraphQL object `ForwardDeliveryResult` with three non-null fields and change
   `beaconForward` from `String!` to that object. Map domain fields without inference.
7. Preserve cancel/update/invite-accept behavior exactly.

**Acceptance:** the authoritative availability check is not a use-case pre-read; a paused
recipient cannot reach `_insertActiveEdge` without holding the same per-user lock as pause.

## UNIT 07 — Server invariant and concurrency proof

**Owns tests only:**

```text
packages/server/test/data/repository/user_availability_repository_pg_test.dart new
packages/server/test/data/repository/forward_edge_availability_pg_test.dart new
packages/server/test/api/controllers/graphql/availability_read_parity_test.dart new
packages/server/test/api/controllers/graphql/forward_delivery_result_test.dart new
```

Use two independent PostgreSQL connections, explicit barriers/completers, and an isolated
database. Do not “prove” races with sequential calls.

Required cases:

1. clear limited vs resume ends open/no row;
2. pause vs clear limited preserves the pause;
3. set limited vs first pause produces the combined row;
4. concurrent first writes never fail the non-empty CHECK;
5. forward pre-read sees open, pause commits before insert lock, forward creates no edge and
   reports the recipient skipped;
6. forward obtains the lock first, inserts, then pause commits: the edge exists because the
   forward linearized first;
7. mixed batch returns delivered/skipped IDs in requested order and emits downstream effects
   only for delivered IDs;
8. limited never blocks or changes ordering;
9. read permission hides block pairs and expired pause-only rows, and exposes no `updated_at`;
10. the typed GraphQL result matches rows actually inserted.

Also run a Hasura diagnostic with more than ten mutually visible users and record whether the
existing `user` select-permission limit caps the SETOF function. Add a regression assertion for
the observed live behavior. Do not change candidate-query scope in this feature: v1 accepts the
pool Hasura returns and applies availability after it.

**Verify:**

```bash
(cd packages/server && dart test -t pg test/data/repository/user_availability_repository_pg_test.dart)
(cd packages/server && dart test -t pg test/data/repository/forward_edge_availability_pg_test.dart)
(cd packages/server && dart test test/api/controllers/graphql/forward_delivery_result_test.dart)
(cd packages/server && dart test -x pg)
```

## UNIT 08 — Client schema, scalar, entities, and read parity

**Owns:**

```text
packages/client/lib/data/gql/calendar_date_serializer.dart new
packages/client/build.yaml
packages/client/lib/data/gql/schema.graphql
packages/client/lib/data/gql/user_model.graphql
packages/client/lib/data/model/user_model.dart
packages/client/lib/data/model/user_public_model.dart
packages/client/lib/features/profile_view/data/repository/mutual_friends_repository.dart
packages/client/lib/features/beacon_view/data/repository/coordination_repository.dart
packages/client/lib/features/forward/domain/entity/forward_delivery_result.dart new
packages/client/lib/features/forward/data/gql/forward_beacon.graphql
packages/client/test/data/gql/calendar_date_serializer_test.dart new
packages/client/test/data/model/availability_read_parity_test.dart new
```

1. Start the updated server, apply metadata/reload the remote schema, then run
   `docker compose run --rm schema_fetcher`. Commit the tracked schema diff.
2. Add lowercase `date` overrides to both Ferry builders and register
   `CalendarDateSerializer`. It maps `YYYY-MM-DD` to `DateTime.utc(y,m,d)` and serializes only an
   exact UTC-midnight date back to that string. It never calls `toLocal()`.
3. Add `user_availability { is_limited resume_on }` to `UserModel`.
4. Map Hasura null relationships to `Availability.open()`. Map V2 date strings with the same
   strict calendar parser. Do not derive/freeze the effective view during mapping.
5. Update all three V2 `Profile` adapters named by architecture §6.
6. Update `forward_beacon.graphql` to select all typed result fields. Add the client Freezed
   `ForwardDeliveryResult`; map the generated response into it in the repository unit that
   follows.
7. Run l10n only later; run Ferry/Freezed codegen now. Do not commit `_g/`.
8. Run the serializer test on VM and Chrome. It must prove a date round-trips unchanged under a
   non-UTC process/browser timezone and rejects non-midnight serialization.

**Acceptance:** `rg "toLocal\("` over the calendar serializer and availability mapper files is
empty; every V2 adapter test fails if availability is removed.

## UNIT 09 — Client availability commands and own-profile state

**Owns:**

```text
packages/client/lib/features/profile/data/gql/availability_set_limited.graphql new
packages/client/lib/features/profile/data/gql/availability_pause.graphql new
packages/client/lib/features/profile/data/gql/availability_resume.graphql new
packages/client/lib/data/service/remote_api_client/build_client.dart
packages/client/lib/features/profile/domain/port/profile_repository_port.dart
packages/client/lib/features/profile/data/repository/profile_repository.dart
packages/client/lib/features/profile/ui/bloc/profile_cubit.dart
packages/client/lib/data/repository/mock/client_repository_mocks.dart (source annotations only)
packages/client/test/features/profile/profile_availability_cubit_test.dart new
```

1. Register all three operation names in `_tenturaDirectOperationNames`.
2. Add these exact repository-port methods and implementations:
   `setAvailabilityLimited({required String profileId, required bool isLimited})`,
   `pauseAvailability({required String profileId, required DateTime resumeOn})`, and
   `resumeAvailability({required String profileId})`. Each returns `Future<void>`, sends exactly
   one mutation, then refetches the own profile and emits the normal repository update event. Do
   not send `profileId` to the self-only mutation and do not optimistically invent server state.
3. Add `ProfileCubit.setAvailabilityLimited(bool)`, `pauseAvailability(DateTime)`, and
   `resumeAvailability()` with command-local loading/error handling. On success rely
   on the repository event/refetch; on failure retain the previous profile and show one error.
4. Add a routing test proving all three requests use V2, not Hasura.
5. Add Cubit tests for success, failure rollback, combined state, and no duplicate user-visible
   effects.

**Acceptance:** profile Cubit still injects one repository port and imports no data service.

## UNIT 10 — Calendar presets, formatting, and localization

**Owns:**

```text
packages/client/lib/domain/util/availability_presets.dart new
packages/client/lib/ui/utils/calendar_day_display.dart new
packages/client/lib/ui/utils/beacon_card_deadline.dart
packages/client/lib/ui/utils/availability_line.dart new
packages/client/l10n/app_en.arb
packages/client/l10n/app_ru.arb
packages/client/test/domain/util/availability_presets_test.dart new
packages/client/test/ui/utils/calendar_day_display_test.dart new
packages/client/test/l10n/availability_localization_test.dart new
```

1. Pure presets take `todayUtc`: tomorrow `+1`; this weekend = next Monday (`8 - weekday`
   days, so Monday means the following Monday); one week `+7`; one calendar month with day
   clamped to the target month's final day. A picked local date becomes
   `DateTime.utc(picked.year,picked.month,picked.day)`.
2. Extract a pure calendar-day formatter. For a future date less than seven calendar days away,
   use localized weekday; otherwise localized date. It accepts date-only values and never
   localizes them.
3. Extend `beaconCardCalendarDeadlineStatus` to use the shared formatting branch while preserving
   its instant/local-date semantics for beacon deadlines. Do not pass availability dates through
   the beacon helper's `toLocal()` path.
4. Add every architecture §10 key in EN/RU plus:
   - `availabilityDeliveredPartialMany(n,m,count)` for two or more skipped people;
   - sheet title, control descriptions, preset labels, Pause, Change, and date-picker label keys
     needed by UNIT 11;
   - person-forward unavailable banner copy needed by UNIT 15.
5. English uses Request/Chat; Russian uses second person for self and third person for others,
   with no gendered predicative adjective.
6. Run `flutter gen-l10n`, terminology test, and a human review of both ARB diffs.

**Acceptance:** boundary tests cover 6/7 days, month ends, leap year, Monday/Sunday weekend,
90-day horizon, and no timezone day shift.

## UNIT 11 — Own-profile control and status

**Owns:**

```text
packages/client/lib/features/profile/ui/sheet/availability_sheet.dart new
packages/client/lib/features/profile/ui/screen/profile_screen.dart
packages/client/lib/features/profile/ui/widget/profile_body.dart
packages/client/test/features/profile/availability_sheet_test.dart new
packages/client/test/features/profile/profile_availability_golden_test.dart new
```

1. Add the status immediately under the description. Always show own open/limited/paused; show
   the second “Then: only important requests” line for limited+paused.
2. Add a `Change` text action that opens the modal sheet. Do not add a Settings entry.
3. Sheet has exactly two independent controls: immediate limited switch; pause preset/date plus
   explicit Pause button; Resume now only while effectively paused.
4. `showDatePicker` first selectable day is tomorrow and last is `todayUtc + 90`; echo the
   resolved UTC calendar date before enabling Pause.
5. Disable only the command currently in flight. Keep the sheet open after limited toggle and
   update its local displayed value from the Cubit's confirmed profile. Close after successful
   Pause or Resume; retain state and show error on failure.
6. Use `TenturaStatusText`: open neutral, limited info, own paused warn. No icon/chip/badge.
7. Widget/golden cases: open, limited, paused, limited+paused two-line, loading, error, compact,
   expanded, and text scale 1.3. Inspect the regenerated PNG before accepting it.

## UNIT 12 — Other-profile and graph action policy

**Owns:**

```text
packages/client/lib/ui/model/person_action_policy.dart
packages/client/lib/features/profile_view/ui/widget/profile_view_body.dart
packages/client/lib/features/graph/ui/widget/graph_person_context_panel.dart
packages/client/test/ui/model/person_action_policy_test.dart
packages/client/test/features/profile_view/profile_view_body_action_policy_test.dart
packages/client/test/features/graph/graph_person_context_panel_test.dart
```

1. Add a testable `todayUtc` parameter/default to policy construction.
2. Preserve all non-request actions. Apply availability as an override to request mechanisms:
   - a pre-existing `sendRequest` primary action becomes `none`;
   - a pre-existing `trust` primary action remains `trust`;
   - `showRequestOptions` becomes false while paused;
   - `canDirectSendRequest` becomes false;
   - `showSecondaryTrust` remains whatever the trust policy computed.
3. Both profile and graph render non-open availability after presence and before trust relation.
   Others use neutral tone. Limited is information only and changes no action.
4. Render dedicated paused explanation; do not reuse a branch that exposes Request options.
5. Tests cover every trust/MR row with open/limited/paused, plus resume-day equality.

**Acceptance:** paused removes every person-targeted send door on both surfaces without removing
Trust; limited changes labels only.

## UNIT 13 — Picker hosts, row precedence, and band exclusion

**Owns:**

```text
packages/client/lib/features/forward/ui/model/forward_recipient_row_host.dart new
packages/client/lib/features/forward/domain/entity/forward_candidate.dart
packages/client/lib/features/forward/domain/use_case/forward_case.dart
packages/client/lib/features/forward/ui/bloc/forward_state.dart
packages/client/lib/features/forward/ui/widget/forward_recipient_row.dart
packages/client/lib/features/forward/ui/widget/forward_recipient_picker.dart
packages/client/lib/features/forward/ui/widget/forward_band_strip.dart
packages/client/lib/features/forward/ui/widget/forward_search_overlay.dart
packages/client/lib/features/forward/ui/widget/lineage_suggestions_sheet.dart
packages/client/test/features/forward/forward_state_scope_test.dart
packages/client/test/features/forward/forward_recipient_picker_test.dart
packages/client/test/features/forward/ui/widget/forward_band_strip_test.dart
packages/client/test/features/forward/forward_recipient_host_policy_test.dart new
packages/client/test/golden/typography_overhaul_test.dart
```

1. Add `canForwardToOn(todayUtc)` and keep the UI getter as a thin call using current UTC date.
2. Do not change `isUnseen`, unseen row count, already-involved semantics, MR sort, or dead
   `computeBeaconListSections` beyond compilation needs.
3. Required host enum values:
   `pickerStandard`, `pickerLineage`, `pickerBand`, `pickerSearch`, `lineagePreview`.
   All except `lineagePreview` expose availability. Make `host` required on every
   `ForwardRecipientRow` call so a future host cannot silently inherit behavior.
4. Implement exact row precedence: tier evidence; hidden presence line; not reachable; any
   already-ineligible involvement (`author`, `declined`, `helpOffered`, `withdrawn`,
   `forwardedByMe`); then availability. Limited replaces presence but keeps relation. Paused
   replaces presence/relation only for otherwise-forwardable unseen/forwarded/watching rows.
5. Allow a selected row to invoke deselection even after it becomes paused; never allow selecting
   a new paused row.
6. After band fetch, remove rows whose matched candidate is paused on `todayUtc`; preserve order
   and provenance for survivors. Do not modify the server band API/recommender.
7. Search and all picker variants pass a showing host. Read-only lineage suggestions pass
   `lineagePreview` and show neither limited nor paused status.
8. Golden/widget matrix covers open, limited, paused, each precedence override, selected-paused
   deselection, every host, and band exclusion.

**Acceptance:** the required enum makes the D19 host inventory compile-enforced; unseen count
equals visible unseen row count including paused rows.

## UNIT 14 — Picker preselection, expiry refresh, and delivery UX

**Owns:**

```text
packages/client/lib/features/forward/data/repository/forward_repository.dart
packages/client/lib/features/forward/domain/use_case/forward_case.dart
packages/client/lib/features/forward/ui/bloc/forward_cubit.dart
packages/client/lib/features/forward/ui/bloc/forward_state.dart
packages/client/lib/features/forward/ui/message/forward_messages.dart
packages/client/lib/features/beacon_create/ui/bloc/beacon_create_cubit.dart
packages/client/lib/features/beacon_create/ui/dialog/beacon_send_confirmation_dialog.dart
packages/client/test/features/forward/forward_cubit_preselect_test.dart
packages/client/test/features/forward/forward_cubit_candidates_load_test.dart
packages/client/test/features/forward/forward_cubit_live_sync_test.dart
packages/client/test/features/forward/forward_cubit_attribution_test.dart
packages/client/test/features/forward/forward_cubit_band_provenance_test.dart
packages/client/test/features/forward/forward_delivery_result_test.dart new
packages/client/test/features/forward/person_forward_case_test.dart
packages/client/test/features/beacon_create/beacon_send_confirmation_dialog_test.dart new
```

1. Change repository/use-case `forwardBeacon` to return client `ForwardDeliveryResult` from the
   server fields. Do not infer delivery from a reload.
2. Gate lineage auto-selection and `initialSelectedIds` with `canForwardToOn(todayUtc)` at load.
   Record availability-dropped preselected IDs so they can be reported if the user sends.
3. At send, snapshot original requested IDs first. Remove only IDs now blocked by availability;
   keep them in the requested denominator. Apply the existing hard validation to remaining
   non-availability ineligibility instead of mislabeling it as a pause.
4. If no IDs remain, do not call the mutation; create a successful processed outcome with zero
   delivered and all requested availability-skipped. If IDs remain, combine local availability
   skips with the server skip list, deduplicated in original requested order.
5. Expand `ForwardDeliveryOutcome` to carry requested IDs, delivered IDs, skipped IDs, and at
   most the display data needed for one-name/many-count copy. `failed` remains only for command
   failure.
6. Non-embedded flow: full delivery uses existing success copy; partial/zero delivery uses one
   name or skipped count and then navigates back. Embedded beacon-create flow stores the exact
   outcome and its confirmation dialog renders delivered `N of M`, never selected count.
7. Add a single expiry timer in `ForwardCubit` for the earliest future `resumeOn`. At the UTC
   boundary, reload candidates/band and reschedule. Add an `AppLifecycleListener` resume callback
   that performs the same reevaluation. Cancel timer/listener in `close`; inject clock/timer
   factories for deterministic tests.
8. Tests cover local strip, server race skip, mixed local/server skip, zero delivery, full
   delivery, single/many copy, timer boundary, app resume, disposal, and no duplicate effect from
   the repository change stream.

**Acceptance:** every displayed delivery count is based on `deliveredRecipientIds`; no post-send
diff or requested-count success message remains.

## UNIT 15 — Deep-link person-forward gate

**Owns:**

```text
packages/client/lib/features/forward/ui/bloc/person_forward_state.dart
packages/client/lib/features/forward/ui/bloc/person_forward_cubit.dart
packages/client/lib/features/forward/ui/screen/person_forward_screen.dart
packages/client/lib/features/forward/ui/message/person_forward_messages.dart
packages/client/test/features/forward/person_forward_cubit_test.dart
packages/client/test/features/forward/person_forward_screen_test.dart new
```

1. Add `canSendOn(todayUtc)` and make `canSend` its clock-reading wrapper. Pause is an additional
   condition; `PersonForwardBlock` remains unchanged.
2. Recheck availability in `PersonForwardCubit.send` immediately before the mutation. Inspect
   the typed result: show sent/navigate only when the person ID is delivered; show availability
   copy when skipped.
3. On the deep-linkable screen, render the neutral paused banner using the existing unreachable
   banner layout. Disable existing-request Send and the “New request” path while paused.
4. Limited renders its neutral informational line but does not disable either path.
5. Tests cover direct deep link, existing request, new request, pause race after load, limited,
   resume-day equality, and preserving existing block/lifecycle reasons.

**Acceptance:** no UI entry path can newly involve a paused subject, and a server skip is never
reported as sent.

## UNIT 16 — Release gate and cache-buster

**Owns:**

```text
packages/client/pubspec.yaml
packages/client/web/index.html
packages/server/lib/env.dart
.env.example
```

1. Reconfirm baseline client version is `5.12.1`; otherwise stop per §1.
2. Set client version to `5.13.0`.
3. Set `flutter_bootstrap.js?v=5.13.0` in tracked `web/index.html`. Do not edit or stage
   skip-worktree `web/manifest.json`.
4. Set `kDefaultMinClientVersion = '5.13.0'` and synchronize the commented `.env.example`
   default/documentation.
5. Run the version-consistency tool/build hook and verify `git diff` contains all four intended
   paths only for this unit.

**Acceptance:** old clients cannot receive the new `beaconForward` object while expecting a
String; source cache-buster exactly matches pubspec.

## UNIT 17 — End-to-end and closeout

1. Start isolated/local infrastructure, run the updated server, apply Hasura metadata, reload the
   remote schema, and rerun schema fetch. A second fetch must produce no diff.
2. API walkthrough with Alice/Bob/Carol:
   - Carol sets limited; Alice sees the label and can forward;
   - Carol pauses; Alice sees disabled unseen row/profile/graph/person-forward gates;
   - an already-open Alice session attempts Bob+Carol and receives delivered Bob/skipped Carol;
   - existing Carol interactions remain unchanged;
   - Carol resumes and the row becomes selectable;
   - limited+paused resumes to limited;
   - blocked viewers cannot read availability.
3. Prove no availability write creates realtime, Updates, push, or notification records and does
   not alter beacon/forward/participant/help-offer/room rows.
4. Search for forbidden leakage: no `updated_at`, no availability instant, no `toLocal()` on
   availability dates, no presence/WebSocket implementation reuse, no Settings tile, and no
   availability status in the read-only lineage preview.
5. Run all checks below. Fix only regressions caused by this plan. Record unrelated failures with
   exact command/output and do not claim the plan complete.
6. Append final journal evidence, current `git status --short`, commit list, remaining manual
   items, and explicit acceptance/rejection of every invariant in architecture §14.

**Plan-wide verification:**

```bash
dart test
(cd packages/tentura_lints && dart test)
./scripts/check-custom-lints.sh packages/server
./scripts/check-custom-lints.sh packages/client
bash scripts/check-user-facing-terminology.sh
(cd packages/server && dart test -x pg)
(cd packages/server && dart test -t pg)
(cd packages/client && flutter gen-l10n)
(cd packages/client && dart run build_runner build -d)
(cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos)
(cd packages/client && flutter test --dart-define=ENV=test)
(cd packages/client && flutter test --platform chrome test/data/gql/calendar_date_serializer_test.dart)
git diff --check
```

## 4. Final acceptance checklist

- [ ] Architecture D1–D30 and the S10/S12 closures in this plan are implemented.
- [ ] All three mutations are self-only, non-null, V2-routed, and use-case-owned.
- [ ] `m0148` is logged/sparse, has no backfill/creation trigger, and is in rollback simulation.
- [ ] `updated_at` and any instant are absent from public schemas, maps, and entities.
- [ ] Client/server share the UTC-calendar comparison and equality boundary.
- [ ] PostgreSQL two-connection tests prove command independence and pause/forward ordering.
- [ ] Server result, snackbar, and create confirmation report actual inserted recipients.
- [ ] Every server public-user producer and client V2 adapter carries availability.
- [ ] Host enum makes all picker render/no-render choices explicit.
- [ ] Band excludes paused candidates; unseen retains paused rows and row-count semantics.
- [ ] Own profile, other profile, graph, picker, search, and person-forward match the tone/action
      rules; lineage preview and non-send surfaces do not render availability.
- [ ] No existing interaction is withdrawn or gated; invite acceptance remains availability-blind.
- [ ] EN/RU copy is Request/Chat terminology-safe and human-reviewed for gender neutrality.
- [ ] Client `5.13.0`, web cache-buster `5.13.0`, server minimum `5.13.0` match.
- [ ] All plan-wide checks pass, or remaining failures are explicitly scoped and the plan remains
      incomplete.

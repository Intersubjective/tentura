# Post + Constellation composer — step-by-step implementation plan

**Status:** rev 2 (2026-10-02). Rev 2 applies the Codex (gpt-6.1-sol, high) review of rev 1
(23 findings, §6). Baseline: `main` at `cdbe19d3a` (closure + trust redesign merged; latest migration
`m0208` `utc_today()`).
**For:** an implementer (human or model) who follows steps literally and works test-first, one unit
at a time. Every unit lists its goal, the exact files, the steps, the tests to write **first**, and
a "done when" command. Do not skip units or change their order unless the dependency column allows
it.

**Sources of truth (read before starting any unit):**
1. `docs/plans/post-and-constellation-composer-plan.md` (rev 5) — the design. "Plan §4.5" points
   there.
2. `docs/plans/post-ux-mockups.md` — every user-facing string and layout. Copy quoted below comes
   from there; use it verbatim.

If a step here contradicts the design plan, stop and report it; do not guess. Line numbers are from
2026-10-02 and drift: if a quoted line does not match, search for the named symbol; if the symbol
itself is missing, stop and report it.

---

## 0. Rules for every unit

### 0.1 Repository conventions

- Read `AGENTS.md`, `.cursor/rules/architecture.mdc` and `.cursor/rules/terminology.mdc` once.
  Domain code (`packages/server/lib/domain/**`, `packages/client/lib/**/domain/**`) must not import
  `data/`, `api/` or `ui/`. Repositories return domain entities. Use cases take ports.
- Users see **Request** / «запрос», **Post** / «пост», **Chat** / «чат». Code keeps `beacon_*`.
- Never edit generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`,
  `*.mocks.dart`, `lib/ui/l10n/*`) by hand; regenerate. After changing DI annotations, freezed
  classes, `@GenerateMocks` lists, l10n or GraphQL documents:
  - server: `cd packages/server && dart run build_runner build --delete-conflicting-outputs`
  - client: `cd packages/client && flutter gen-l10n && dart run build_runner build --delete-conflicting-outputs`
- **Migrations — one new migration per unit.** A unit that changes SQL creates its **own** new
  migration file with the next free version (`ls packages/server/lib/data/database/migration/`;
  `m0208` is taken on `main`, so the first one is `m0209`). Never edit or extend a migration that
  an earlier unit created — migrant records a version once and never re-runs it
  (`_migrations.dart:39`). The planned numbers below (m0209 … m0214) are only a guide; if a number
  is taken when you start, use the next free one and keep going. Shape: like `m0206.dart` —
  `part of '_migrations.dart';`, a `///` doc comment, `final m0NNN = Migration('0NNN', [ '''SQL''',
  r'''SQL with $$''', ]);`, one statement per entry; register it in `_migrations.dart` (the `part`
  line and `_allMigrations`). Function bodies are not validated during migration, so every new SQL
  function needs a pg test that calls it. Migrations must not call `mr_*` functions. Each migration
  test also checks the **upgrade path**: migrate a database through the previous version
  (`setUpDisposablePgWriter(target:, lastInclusiveVersion: '<previous>')`), then
  `migrateDbSchema(writer)`, then assert.
- **The m0199 test pins the latest version.** `packages/server/test/data/database/m0199_fact_history_migration_pg_test.dart`
  (`'the registry now reaches 0208'`, ~:57-66) asserts the literal `'0208'`. S1 changes it to
  `migrationsForTesting.last.version` and renames the test; later units then need no change there.
- **Transactions (server).** Use cases get `MutatingUnitOfWorkPort` and call
  `_uow.run(actorUserId: …, action: () async { … })`; attention-producing mutations use
  `TransactionalAttentionCase.runAction(actorUserId:, action: (tx) async { … })`. Nested calls with
  the **same actor** join the outer transaction (`TenturaDb.withMutatingUser`,
  `tentura_db.dart:180-205`). Repository ports take domain arguments only. Raw SQL:
  `_db.customStatement(sql, [args])` / `_db.customSelect(...)`.
- **Lock order (plan §4.10).** Global hierarchy advisory lock → per-request advisory lock
  `pg_advisory_xact_lock(hashtextextended(@beaconId, 4242))` → beacon row lock → recipient
  availability locks → trust pair locks. All Post paths call `PostLockPort.lockForPostMutation`
  (unit S11a) first and re-check everything mutable after it.
- **Exceptions (server).** New exceptions in `packages/server/lib/domain/exception.dart` as
  `final class XException extends ExceptionBase` with a `const` ctor passing
  `code: const BeaconExceptionCodes(BeaconExceptionCode.x)`; codes appended to `BeaconExceptionCode`
  (`lib/domain/exception_codes.dart`, append-only; next free wire code on 2026-10-02 is 1321).
  Mirror a new code on the client like `packages/client/lib/features/beacon/domain/beacon_hierarchy_exception.dart:76`.
- **Policies (server).** `abstract final class XPolicy { XPolicy._(); static … }` in
  `packages/server/lib/domain/policy/` (template `beacon_room_lifecycle_write_policy.dart`).
- **New V2 mutation/query (server):** pattern of `mutation_notification_preferences.dart`
  (constructor injection with `GetIt` fallback, `all` list, static input fields) and
  `mutation_beacon.dart:49-69` (`InputFieldId.field`, `getCredentials(args).sub`); register in
  `mutation/_mutations_all.dart` (queries: the matching aggregator in
  `packages/server/lib/api/controllers/graphql/query/`). Test pattern:
  `test/api/controllers/graphql/mutation_availability_test.dart`.
- **Hasura.** `hasura/metadata.json`. Computed field form:
  `{"name":"x","definition":{"function":{"name":"beacon_get_x","schema":"public"},"session_argument":"hasura_session","table_argument":"beacon_row"}}`
  (see `is_pinned` ~:159). Role `user` select permission columns end with `"is_discoverable"`
  (~:292); computed fields list ~:294.
  - **Every unit that edits `metadata.json` adds two tests:** (a) a JSON-shape test asserting the
    new computed field/columns/permissions are present (for the metadata-parsing pattern, see
    `packages/server/test/architecture/hasura_metadata_closure_tables_untracked_test.dart` --
    `m0203_closure_hasura_metadata_test.dart` was renamed/rewritten to this file in a1707d683 and no
    longer covers the same assertion); and (b) a
    behavioural pg test through `IsolatedHasuraSession` (`test/support/isolated_hasura_session.dart`)
    that queries/mutates as role `user` and asserts the result, and calls
    `session.assertMetadataConsistent()` (added by unit T0). `applyRepoMetadata` uses
    `allow_inconsistent_metadata: true` (:122-133), which silently drops an invalid permission — a
    JSON-shape test alone proves nothing.
  - **No `now()` in Hasura filters.** Compare dates with `utc_today()` (m0208); time windows are
    computed on the client or in Tentura SQL.
- **Client GraphQL schema.** After server units that add V2 fields: start the changed server, apply
  Hasura metadata (`./scripts/hasura_apply_metadata.sh`), reload the `tentura` remote schema
  (`DEVELOPMENT.md` §Hasura), `docker compose run --rm schema_fetcher`, then write `.graphql`
  documents (naming like `features/closure/data/gql/beacon_close.graphql`) and run build_runner. If
  the local stack is unavailable, edit `packages/client/lib/data/gql/schema.graphql` by hand to
  match the server SDL exactly and say so in the commit message.
- **Feature gate.** `packages/client/lib/consts.dart` gets `const kPostsEnabled = false;` in unit
  C0. Every client entry point that lets a user *create* a Post (C1 entry buttons, K2c canvas entry,
  the Constellation toolbar button) checks it. Unit V flips it to `true`. Receiving and viewing
  Posts needs no gate (nobody can create one before V).
- **UI:** design system only (`context.tt` tokens, `TenturaText.*`); no raw colors, font sizes,
  `EdgeInsets` or `BorderRadius` from numbers. Invoke the `material-3-flutter` skill before writing
  UI. Never rely on long-press alone; add secondary-tap and a visible button.
- **l10n:** keys in `packages/client/l10n/app_en.arb` and `app_ru.arb`; Russian copy from the
  mockups verbatim; English a faithful translation.
- **Mocks:** server and client use **mockito** (`class X extends Mock implements Y` or
  `@GenerateMocks`) and hand-written fakes under `test/support/`. No `bloc_test`: drive cubits
  directly and `await Future<void>.delayed(Duration.zero)`.
- No golden tests.

### 0.2 Running tests (always wrapped, always one at a time)

```bash
# server, one file
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test <file>
# server, Postgres test file(s): REQUIRED mode — fails instead of skipping without Postgres (unit T0)
cd packages/server && TENTURA_PG_TESTS_REQUIRED=1 ../../scripts/run_with_test_cleanup.sh --timeout 30m -- dart test <file>
# server suites (unit V)
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --exclude-tags pg
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 30m -- dart test --tags pg --exclude-tags mr
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 30m -- dart test --tags mr -j 1
# client, one file or directory
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 45m -- \
  flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env <path>
# graph package
cd packages/force_directed_graphview && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- flutter test
# lints
./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/server
./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/client
```

Never run two wrapped commands at the same time (they delete each other's temp files). pg tests
follow `packages/server/test/data/database/m0206_noisy_contact_pg_test.dart` (`@Tags(['pg'])`,
`DisposablePgTarget.fromNamedEnvironment(...)`, `setUpDisposablePgWriter`, skip reason from the T0
helper). Use-case pg tests with real repositories **and real attention dispatch**
(`AttentionDispatchRepository`) follow
`packages/server/test/domain/use_case/help_offer_obligation_settlement_pg_test.dart`; do not copy
`_NoopAttentionDispatch` from `forward_reason_reconciliation_pg_test.dart` when the test asserts
receipts.

### 0.3 Definition of done for every unit

1. The unit's new tests were written first and failed for the expected reason (spike S0 and pure
   characterization tests are exempt), and now pass.
2. pg and Hasura tests ran in REQUIRED mode (§0.2) and the output shows them **executed, not
   skipped**. A skipped test never satisfies "done".
3. The existing tests named in the unit still pass.
4. `dart analyze`/`flutter analyze` show no new issues **on the files your diff actually touches** --
   scope the command to those files (or `git diff --name-only` them in), not a whole directory or
   package. A sibling file in the same directory that happens to be pre-existing-dirty (edited
   elsewhere in the same unit, or by an earlier unit) can carry unrelated pre-existing warnings;
   those are out of scope and are not "new issues" from this unit. Confirm pre-existing with
   `git blame` on the flagged line and `git diff --unified=0 <file>` to see what you actually
   changed in it, rather than assuming directory-wide cleanliness.
5. Custom lints pass for the touched package; the count in `scripts/custom-lint-baseline.txt` may
   only go down.
6. A unit compiles and passes on its own and does not implement a later unit's scope. If a step
   reveals work outside the unit, stop and report it.
7. One commit per unit: `feat(post): <unit id> <short title>` (or `refactor`, `test`, `chore`,
   `docs`), ending with the attribution line required by the session.

### 0.4 Glossary

| Term | Meaning |
|---|---|
| Post | `beacon` row with `kind = 1` |
| Request | `beacon` row with `kind = 0` |
| root message | the author's first room message of a Post; `beacon.post_root_message_id` |
| addressee | `beacon_participant.role = 6`: admitted by an inbound forward edge (Post), or kept after conversion |
| admitted / left | `beacon_participant.room_access` 3 / 5 (`RoomAccessBits`) |
| open family | beacon status in {0, 7, 8} |
| first response | a non-author member's first message or first reaction in a Post |
| REQUIRED mode | `TENTURA_PG_TESTS_REQUIRED=1`: pg/Hasura tests fail instead of skipping |

---

## 1. Unit map (execution order)

Order rule: risky and uncertain units first, so that a surprise changes the plan before many units
depend on it. Within the same risk level, foundations before consumers.

| # | Id | Title | Depends on | Area |
|---|---|---|---|---|
| 1 | T0 | Test infra: REQUIRED mode, `assertMetadataConsistent()` | — | server tests |
| 2 | S0 | Spike: one transaction across publish, forward, message (real dispatch) | T0 | server tests |
| 3 | S1 | Schema m0209: kind, policy, activity, root, pinned_at; Drift; entity; mapper; consts | T0 | server |
| 4 | S2 | Forward ⇒ admission + helper/bond views (m0210) | S1 | server SQL |
| 5 | S11a | `PostLockPort`; ForwardCase checks under the lock for Posts; forward ∥ block | S2 | server |
| 6 | K0 | Empty-canvas gestures in `force_directed_graphview` | — | graph pkg |
| 7 | G2a | Semantic edge ids through `EdgeDetails`, scene, controller, painter | — | client graph |
| 8 | R1a | `RoomHost` + `RoomCapabilities`; capability propagation through factories and fetches | — | client |
| 9 | R1b | `BeaconRoomSurface(host:)` + widget gating | R1a | client |
| 10 | S5 | Kind-aware creation: GraphQL, Drift, policy, port, mutation | S1 | server |
| 11 | S4a | `BeaconForwardPolicy` on forward and invite paths; `beaconForwardingOpen` | S11a, S5 | server |
| 12 | S4b | `viewer_can_forward` (m0211) + Hasura columns/computed field | S4a | server, hasura |
| 13 | S6 | `postPublish` | S0, S4a, S5 | server |
| 14 | S11b | Concurrency: publish ∥ block, cancel ∥ cancel, invite accept ∥ block | S6 | server tests |
| 15 | S3a | `BeaconKindPolicy` guards in use cases + room-mutation table | S6 | server |
| 16 | S3b | DB help-offer guard (m0212) + Hasura help-offer kind check | S3a, S4b | server, hasura |
| 17 | S3c | Request-only SQL exclusions (m0213) | S6, S3b | server |
| 18 | S3d | Request-only audit pg test | S3a, S3b, S3c | server tests |
| 19 | S8 | Block-aware Post room gate + Hasura Post-only branch | S6 | server, hasura |
| 20 | S9 | `postLeave` / `postReturn` + Hasura inbox kind check | S6, S11a | server, hasura |
| 21 | S7 | First-response claim (m0214) + `postFirstResponse` + contract | S6, S3c | server, contract |
| 22 | S10a | Attention projection: receipts carry kind, root excerpt, image | S6 | server |
| 23 | S10b | Post grouping, position, pinned and dismiss semantics | S10a, S7 | server |
| 24 | S10c | In-app mute for Posts | S10b | server |
| 25 | S12a | `beaconConvertToRequest` (single UPDATE) + system kind 4 + forward ∥ convert | S3a, S5, S11a | server |
| 26 | S12b | Intermediate role-6 server rules | S12a, S9 | server |
| 27 | S13 | Root delete = Post delete | S6 | server |
| 28 | S14 | Notification pipeline for Posts | S7 | server |
| 29 | S15 | `myPosts` query | S6, S9 | server |
| 30 | G1a | Field payload: posts, memberWebs, hiddenReachCount, kind-aware pinned records | S8 | server |
| 31 | G1b | `beaconMemberWebs(id)` query | G1a | server |
| 32 | C0 | Client schema refresh, `Beacon` fields, capability truth table, Request-only queries, flag | S1–S15, G1b | client |
| 33 | R2 | `ForwardTargetProfile` | C0 | client |
| 34 | C2a | Kind-aware route host + `PostViewCubit` + minimal Post screen | C0, R1b | client |
| 35 | C2b | Post app bar, overflow, pinned strip, root-delete confirm, kind-4 renderer | C2a | client |
| 36 | C2c | Participants screen | C2a | client |
| 37 | C1 | Post create screen | C0, R2, C2a | client |
| 38 | C3 | «Для вас» Post row (fetch → row) | C0, S10b | client |
| 39 | C4 | «Разговоры» tab | C0, S15 | client |
| 40 | C5 | Mute, pin, leave/return UI | C2b, C4 | client |
| 41 | C6 | Convert to Request flow | C2b, S12a | client |
| 42 | C7 | Intermediate participant state UI | C6, S12b | client |
| 43 | K1 | `RadiusRecipientSelection` (pure) | — | client |
| 44 | G2b | Client field entities + Post projection (composition, nodes, labels, anchors) | C0, G2a | client |
| 45 | G2c | Post webs, fade, «+N» | G2b | client |
| 46 | G3 | Request webs on selection | G2c | client |
| 47 | K2a | Composer cubit: draft lifecycle + selection adapter + `ForwardCubit.setSelection` | K1, R2, C1 | client |
| 48 | K2b | Composing phase: draft node, widened composition, draft edges, tap toggle | K2a, G2c | client |
| 49 | K2c | Radius circle + handle drag + canvas entry gestures | K2b, K0 | client |
| 50 | K3a | Composer sheet + list handoff | K2c | client |
| 51 | K3b | Publish + anchor + full-form handoff | K3a | client |
| 52 | D1 | Doc amendments A1–A7 | — | docs |
| 53 | V | Release: flag on, versions, full checks | all above | all |
| 54 | E1 | Web end-to-end journeys | V | client e2e |

T0, K0, G2a, R1a, K1 and D1 have no server dependency. K0, G2a and R1a/R1b are early only because
they are risky refactors of shared code. Units that each add a migration (S1, S2, S4b, S3b, S3c,
S7) are chained in that order so migration numbers are allocated without collisions.

---

## 2. Infrastructure and spikes

### T0 — Test infra: REQUIRED mode and Hasura consistency

**Goal:** make "done" provable: pg tests must not silently skip; Hasura metadata must be consistent.

**Files**
- modify `packages/server/test/support/disposable_pg_target.dart`: next to `canReachPostgresAdmin`
  (:271) add `Future<String?> pgSkipReason(DisposablePgTarget target, {Map<String, String>?
  environment})` that returns `null` when Postgres is reachable; when not reachable it returns a skip
  reason, **unless** `(environment ?? Platform.environment)['TENTURA_PG_TESTS_REQUIRED'] == '1'`, in
  which case it throws `StateError('Postgres required (TENTURA_PG_TESTS_REQUIRED=1) but not
  reachable')`.
- modify `packages/server/test/support/isolated_hasura_session.dart`: add
  `Future<void> assertMetadataConsistent()` that posts `{"type":"get_inconsistent_metadata","args":{}}`
  to `/v1/metadata` and throws `StateError` listing the inconsistent objects when
  `is_consistent != true`. Make `isDockerAvailable` respect REQUIRED mode the same way (throw
  instead of returning false).
- create `packages/server/test/support/pg_required_mode_test.dart` (pure) and
  `packages/server/test/support/isolated_hasura_consistency_pg_test.dart` (tag `pg`).

**Tests (write first)**
- pure: unreachable target and REQUIRED unset → a non-null reason; REQUIRED=1 → throws.
- pg + Docker: start an `IsolatedHasuraSession`, apply the repo metadata → `assertMetadataConsistent()`
  passes; apply a copy whose beacon permission references a non-existent column → it throws.

**Done when:** `cd packages/server && TENTURA_PG_TESTS_REQUIRED=1 ../../scripts/run_with_test_cleanup.sh --timeout 30m -- dart test test/support/pg_required_mode_test.dart test/support/isolated_hasura_consistency_pg_test.dart`
shows both files executed and green.

### S0 — Spike: one transaction across publish, forward and message

**Goal:** prove that `postPublish` (plan §4.5) can call existing use-case code inside one
`TransactionalAttentionCase.runAction`, with **real** attention dispatch, and that a failure in the
last step rolls everything back. Characterization: no production code. Tests are expected to pass
on first run; if they do not, that is the finding.

**Files**
- create `packages/server/test/domain/use_case/post_publish_transaction_spike_pg_test.dart` (tag `pg`)

**Steps**
1. Wire real repositories, `AttentionDispatchRepository`, `TransactionalAttentionCase`,
   `BeaconCase`, `ForwardCase`, `BeaconRoomCase` the way
   `help_offer_obligation_settlement_pg_test.dart` and the existing ForwardCase / BeaconRoomCase pg
   tests build them (`grep -rln "ForwardCase(" packages/server/test`).
2. Seed author A, two users B and C mutually visible to A (copy the seeding of an existing
   ForwardCase pg test), and a **draft Request** owned by A (the Post kind does not exist yet).
3. Test 1: inside `attention.runAction(actorUserId: A, action: (tx) async { … })` call
   `beaconCase.publishDraft(...)`, `forwardCase.forward(...)` to B and C,
   `beaconRoomCase.createMessage(...)`. Assert: status 0, two edges, one message, `relayReceived`
   receipts for B and C.
4. Test 2: same, then `throw StateError('boom')` after `createMessage`. Assert: still a draft, no
   edges, no message, no receipts/occurrences for this beacon.
5. If Test 1 fails because a use case cannot run nested (actor mismatch, its own commit, a
   persist outside the transaction such as `beacon_room_case.dart:471-473`), write down exactly
   which call and why as a comment at the top of the file, mark that test `skip:` with the reason,
   and **stop**: report it. S6 then extracts that use case's core into a method that takes the open
   transaction.

**Done when:** in REQUIRED mode both tests executed and passed (or the stop condition was reported
with evidence). Commit `test(post): S0 transaction composition spike`.

---

## 3. Server

### S1 — Schema m0209: kind, forward policy, activity, root, pinned_at

**Goal:** plan §4.1.

**Files**
- create `packages/server/lib/data/database/migration/m0209.dart`; register it
- modify `packages/server/lib/data/database/table/beacons.dart`: add `kind` (int, default 0),
  `forwardPolicy` (int, default 1), `lastActivityAt` (nullable timestamp), `postRootMessageId`
  (nullable text); the `beacon_pinned` table class (`grep -rln "beacon_pinned"
  packages/server/lib/data/database/table`): add `pinnedAt`
- create `packages/server/lib/domain/entity/beacon_kind.dart`: `enum BeaconKind { request(0),
  post(1); … static BeaconKind fromValue(int v) }` and `enum BeaconForwardPolicyValue { closed(0),
  open(1); … }`
- modify `packages/server/lib/domain/entity/beacon_entity.dart`: `@Default(BeaconKind.request)
  BeaconKind kind`, `@Default(BeaconForwardPolicyValue.open) BeaconForwardPolicyValue
  forwardPolicy`, `DateTime? lastActivityAt`, `String? postRootMessageId`
- modify `packages/server/lib/data/mapper/beacon_mapper.dart:11-44`: map the four new fields **and**
  `isDiscoverable` (not mapped today)
- modify `packages/server/lib/consts/beacon_room_consts.dart:2-9` (`addressee = 6`) and
  `packages/server/lib/consts/beacon_hierarchy_consts.dart:24-28` (`convertedToRequest = 4`);
  mirror both in `packages/client/lib/domain/entity/beacon_room_consts.dart` (:2-9, :61-65)
- modify `packages/server/test/data/database/m0199_fact_history_migration_pg_test.dart` (§0.1)
- create `packages/server/test/data/database/m0209_post_schema_pg_test.dart` (tag `pg`) and
  `packages/server/test/data/mapper/beacon_mapper_kind_test.dart`

**Steps (SQL in m0209, one statement per entry, in this order)**
1. `ALTER TABLE public.beacon ADD COLUMN kind smallint NOT NULL DEFAULT 0, ADD COLUMN forward_policy
   smallint NOT NULL DEFAULT 1, ADD COLUMN last_activity_at timestamptz, ADD COLUMN
   post_root_message_id text REFERENCES public.beacon_room_message(id) ON DELETE SET NULL;`
2. `ALTER TABLE public.beacon ADD CONSTRAINT beacon_kind_range CHECK (kind IN (0, 1));`
3. `ALTER TABLE public.beacon ADD CONSTRAINT beacon_forward_policy_ck CHECK (forward_policy IN (0, 1)
   AND (kind = 1 OR forward_policy = 1));`
4. `ALTER TABLE public.beacon ADD CONSTRAINT beacon_post_shape_ck CHECK (kind = 0 OR (status IN (0,
   2, 3) AND is_discoverable = false AND parent_beacon_id IS NULL AND start_at IS NULL AND end_at IS
   NULL AND title = '' AND description = '' AND cover_image_id IS NULL));` (The existing SQL
   title/description CHECKs already allow `''`; the minimum title length lives in GraphQL and Drift
   and is handled in S5.)
5. `CREATE FUNCTION public.beacon_kind_policy_guard() RETURNS trigger` (`r'''`, `$$`):
   `IF OLD.kind = 0 AND NEW.kind = 1 THEN RAISE EXCEPTION 'beacon kind cannot change from request to post' USING ERRCODE = 'check_violation'; END IF;`
   `IF OLD.forward_policy = 1 AND NEW.forward_policy = 0 AND OLD.status <> 3 THEN RAISE EXCEPTION 'forward policy is one-way' USING ERRCODE = 'check_violation'; END IF;`
   `RETURN NEW;`
6. `CREATE TRIGGER beacon_kind_policy_guard_trg BEFORE UPDATE OF kind, forward_policy ON public.beacon FOR EACH ROW EXECUTE FUNCTION public.beacon_kind_policy_guard();`
7. `ALTER TABLE public.beacon_pinned ADD COLUMN pinned_at timestamptz NOT NULL DEFAULT now();`
8. Backfill: `UPDATE public.beacon b SET last_activity_at = coalesce((SELECT max(m.created_at) FROM
   public.beacon_room_message m WHERE m.beacon_id = b.id AND m.system_message_kind IS NULL),
   b.published_at, b.created_at);`
9. `CREATE FUNCTION public.beacon_bump_last_activity(p_beacon text, p_at timestamptz) RETURNS void`
   = `UPDATE public.beacon SET last_activity_at = GREATEST(coalesce(last_activity_at, p_at), p_at)
   WHERE id = p_beacon;`
10. Three AFTER INSERT triggers with one trigger function each: on `beacon_room_message` (only when
    `NEW.system_message_kind IS NULL`), on `beacon_room_message_reaction` (look up the message's
    `beacon_id`), on `beacon_forward_edge`.

**Tests (write first)**
- pg, full schema: default `kind 0`, `forward_policy 1`; `kind 1` with a title fails
  (`check_violation`); a valid empty Post draft succeeds; `kind 0, forward_policy 0` fails; `kind 1,
  status 6` fails; Request → Post update raises; Post draft `forward_policy` 1 → 0 succeeds, the
  same on status 0 raises, 0 → 1 on status 0 succeeds; a non-system message, a reaction and a forward
  edge bump `last_activity_at`; a system message does not; an older timestamp never lowers it;
  `beacon_pinned.pinned_at` is set; deleting the root message nulls `post_root_message_id`.
- pg, upgrade path: migrate through `'0208'`, insert a Request with a message, migrate → backfilled
  `last_activity_at` equals the message time.
- pure mapper: a row with `kind 1, forward_policy 0, is_discoverable false` maps to `post`,
  `closed`, `isDiscoverable == false`.
- existing: `drift_images_create_table_on_migrated_pg_test.dart`, `m0194_drift_reconciliation_pg_test.dart`,
  `schema_baseline_pg_test.dart`, `migration_registry_test.dart`, the m0199 test.

**Done when:** in REQUIRED mode, `dart test test/data/database/m0209_post_schema_pg_test.dart
test/data/mapper/beacon_mapper_kind_test.dart test/data/database/m0199_fact_history_migration_pg_test.dart
test/data/database/drift_images_create_table_on_migrated_pg_test.dart test/data/database/m0194_drift_reconciliation_pg_test.dart`
(wrapped, in `packages/server`) is green.

### S2 — Forward ⇒ admission for Posts; helper and bond views (m0210)

**Goal:** plan §4.2.

**Files**
- create `m0210.dart`; register it
- create `packages/server/test/data/database/m0210_post_admission_pg_test.dart` (tag `pg`)

**Steps (SQL)**
1. `CREATE FUNCTION public.post_reconcile_admission(p_beacon text, p_user text) RETURNS void`:
   - `IF NOT EXISTS (SELECT 1 FROM public.beacon WHERE id = p_beacon AND kind = 1 AND user_id <> p_user) THEN RETURN; END IF;`
   - `INSERT INTO public.beacon_participant (id, beacon_id, user_id, role, room_access) VALUES (<id expression copied from an existing participant insert — grep "INSERT INTO public.beacon_participant" in m0193.dart>, p_beacon, p_user, 6, 0) ON CONFLICT (beacon_id, user_id) DO NOTHING;`
   - `SELECT role, room_access INTO _role, _access FROM public.beacon_participant WHERE beacon_id = p_beacon AND user_id = p_user FOR UPDATE;`
   - `IF _role <> 6 OR _access = 5 THEN RETURN; END IF;`
   - `_active := EXISTS (SELECT 1 FROM public.beacon_forward_edge WHERE beacon_id = p_beacon AND recipient_id = p_user AND cancelled_at IS NULL);`
   - `IF _active AND _access <> 3 THEN UPDATE … SET room_access = 3, updated_at = now() …; ELSIF NOT _active AND _access = 3 THEN UPDATE … SET room_access = 0, updated_at = now() …; END IF;`
2. `CREATE FUNCTION public.post_admission_on_forward_edge() RETURNS trigger` =
   `PERFORM public.post_reconcile_admission(NEW.beacon_id, NEW.recipient_id); RETURN NEW;` and two
   triggers: `AFTER INSERT ON public.beacon_forward_edge` and `AFTER UPDATE OF cancelled_at ON
   public.beacon_forward_edge`.
3. `CREATE OR REPLACE VIEW public.beacon_admitted_helper` — copy `m0193.dart:4906-4911`, add `AND
   role <> 6`.
4. `person_bond`, `person_bond_peers` (`m0193.dart:3639-3670`) and `person_shared_contexts`
   (`:3702-3712`): copy each definition, add `AND b.kind = 0` next to the status filter; use `CREATE
   OR REPLACE VIEW` / `CREATE OR REPLACE FUNCTION` with the identical signature, whichever each is.

**Tests (write first, pg)**
- forward A → B on a published Post (insert rows directly; `postPublish` does not exist yet) ⇒ B
  has `role 6, room_access 3`; B in `beacon_member`; B not in `beacon_admitted_helper`.
- the same on a Request ⇒ no participant row; forward to the author ⇒ no row.
- cancel the only edge ⇒ 0; edges A → B and C → B, cancel one ⇒ 3; cancel both ⇒ 0.
- B at `room_access 5`, new edge D → B ⇒ 5; cancel all ⇒ 5.
- a steward row for B is unchanged by forward and cancel.
- two addressees of one Post are not in `person_bond`; two helpers of an open Request still are
  (copy the bond fixture: `grep -rln person_bond packages/server/test`).
- an accepted-invite edge (inserted as `user_repository.dart:109-142` does) admits.
- upgrade path from `'0209'`.

**Done when:** in REQUIRED mode `dart test test/data/database/m0210_post_admission_pg_test.dart`
and every test file found by `grep -rln "person_bond\|beacon_admitted_helper" packages/server/test`
are green.

### S11a — `PostLockPort`; ForwardCase checks under the lock for Posts

**Goal:** plan §4.10: one lock helper; for Posts, every mutable check runs after the lock.

**Files**
- create `packages/server/lib/domain/port/post_lock_port.dart`:
  `abstract interface class PostLockPort { Future<void> lockForPostMutation(String beaconId); }`
- create `packages/server/lib/data/repository/post_lock_repository.dart`
  (`@Injectable(as: PostLockPort)`): take the global hierarchy lock with the existing helper (find
  it: `grep -rn "tentura.beacon_hierarchy.v1" packages/server/lib`; `UserBlockCase` uses it at
  `user_block_case.dart:80-83`), then `pg_advisory_xact_lock(hashtextextended($1, 4242))`, then
  `SELECT 1 FROM public.beacon WHERE id = $1 FOR UPDATE`. Run build_runner.
- modify `ForwardCase.forward` (`forward_case.dart:160-339`): load the beacon kind first (cheap
  read). **If the beacon is a Post**, run, inside `runAction` and after `lockForPostMutation`, the
  checks that today run before the transaction (block filter :200-206, `canReadContent` :208-215,
  `allowsForward` :218-222, mutual visibility :235-246, parent-edge checks); then create edges.
  For Requests keep the current order unchanged (extract the checks into one private method called
  from both places; do not duplicate them).
- create `packages/server/test/domain/use_case/post_lock_order_pg_test.dart` (tag `pg`, real
  repositories, §0.2)

**Tests (write first, pg)**
- barrier test: start a forward of a Post from A to B; pause it (an optional
  `@visibleForTesting Future<void> Function()? beforeLockForTest` on `ForwardCase`) after the first
  beacon read; commit "B blocks A" through `UserBlockCase`; resume. Expect the forward to fail with
  the block exception and no edge or admitted row for B.
- 20 rounds, in parallel: A forwards a Post to B ∥ B blocks A. Each round finishes within 10 s with
  no `deadlock_detected` (SQLSTATE `40P01`); afterwards either the forward failed or the edge is
  cancelled and B is not admitted.
- Requests: existing `forward_case_test.dart` and `forward_case_auth_test.dart` green.

**Done when:** in REQUIRED mode `post_lock_order_pg_test.dart` is green three runs in a row
(serially) and the two existing ForwardCase test files are green.

### K0 — Empty-canvas gestures in `force_directed_graphview`

**Goal:** plan §7.1: `GraphView` reports taps, secondary taps and long presses that hit no node.

**Files**
- `packages/force_directed_graphview/lib/src/graph_view.dart` (:38-124): add
  `final void Function(Offset scenePosition)? onCanvasTap, onCanvasSecondaryTap, onCanvasLongPress;`
- `packages/force_directed_graphview/lib/src/configuration.dart` (~:138): the pointer layer is
  enabled today only for node callbacks/dragging; also enable it when any canvas callback is set.
- `packages/force_directed_graphview/lib/src/widget/node_drag_gesture.dart` (hit testing ~:104):
  when a tap / secondary tap / long press hits no node, call the canvas callback with
  `controller.viewportLocalToScene(localPosition)` (exists, `controller.dart:201`). A gesture that
  became a pan (beyond the existing slop) calls nothing.
- create `packages/force_directed_graphview/test/canvas_gesture_test.dart`

**Tests (write first, widget)**
- one node at (0,0), view panned by (100, 50) and scaled 2×: tapping empty space calls
  `onCanvasTap` with the right scene position (±1 px); tapping the node calls `onNodeTap` only.
- secondary tap (`kSecondaryMouseButton`) on empty space → `onCanvasSecondaryTap`; on a node → no
  canvas callback.
- long press on empty space → `onCanvasLongPress`; on a node → no canvas callback.
- a drag on empty space beyond the slop pans and calls no canvas callback.
- only canvas callbacks set (no node callbacks): taps are still reported.
- with all three `null`: existing package tests unchanged.

**Done when:** the graph package suite (§0.2) is green, and in the client
`test/features/constellation/constellation_body_test.dart`,
`constellation_anchor_interaction_test.dart`, `constellation_node_tap_dispatch_test.dart` and
`test/features/graph/` are green.

### G2a — Semantic edge ids

**Goal:** plan §6.4: two edges with the same endpoints and different kinds coexist.

**Files**
- `packages/client/lib/features/graph/domain/entity/edge_details.dart` (equality :22): add a
  `String semanticId` (default: today's `'src->dst'`), include it in `==`/`hashCode`.
- `packages/client/lib/features/constellation/ui/utils/constellation_graph_scene.dart` (:33): resolve
  edges by `semanticId`, not by the endpoint suffix.
- `constellation_cubit.dart` `addEdge` (:2234-2265): key and assert by `semanticId`
  (`'src->dst#kind'`); `constellation_body.dart` painter (:982-984): look up by `semanticId`;
  `force_directed_graphview` controller lookups that key edges by endpoints: switch to the edge
  object / semantic id (search `controller.dart` for edge maps).
- create `packages/client/test/features/constellation/constellation_semantic_edge_id_test.dart`

**Tests (write first):** two edges between the same pair with different kinds **and identical
visual properties** survive `Set` insertion and `reconcileTopology`; each is painted with its own
style; existing edges keep their ids (no behaviour change).

**Done when:** new test + `test/features/constellation/` + `test/features/graph/` + graph package
suite are green.

### R1a — `RoomHost`, `RoomCapabilities`, propagation through factories and fetches

**Goal:** plan §5.3, data side. No widget changes yet; no behaviour change for Requests.

**Files**
- create `packages/client/lib/features/beacon_threads/domain/room_host.dart`: `RoomHost` (plan
  §5.3), `RoomCapabilities` (immutable; `const RoomCapabilities.request()` = all flags on,
  `pinnedStrip: RoomPinnedStrip.requestNow`; `const RoomCapabilities.post()` = all off,
  `pinnedStrip: RoomPinnedStrip.postRoot`), `enum RoomPinnedStrip { requestNow, postRoot }`.
- `ThreadHostCubit` (`thread_host_cubit.dart`, `RoomCubitFactory` typedef :14): the factory and the
  cubit take `RoomCapabilities capabilities` (default `request()`) and pass it to `RoomCubit`.
- `RoomCubit` (`room_cubit.dart:56-90`): ctor param `capabilities` (default `request()`); in
  `_fetchFullSnapshot` (:673-718) skip `fetchBeaconRoomState` and `fetchCurrentCoordinationPlan`
  when `!plan`, `fetchFactCards` when `!facts`, `fetchOpenCoordinationBlocker` when `!blocker`,
  `fetchCoordinationItems` when `!coordinationItems`; guard the facts-only refresh (:348-351) and
  every other Request-only refresh path (search `RoomCubit` for every `fetch*` call) the same way.
- `BeaconViewCubit` `implements RoomHost` (getters from state; `changes` = `stream.map((_) {})`;
  capabilities `request()`).
- create `packages/client/test/features/beacon_threads/room_capabilities_test.dart`

**Tests (write first):** with `post()` and a `FakeBeaconThreadsRepository` (`room_cubit_fakes.dart:40`)
whose Request-only methods **throw**, `RoomCubit.load()` and every refresh path succeed; with
`request()` they call every fetch; a `ThreadHostCubit` built with `post()` produces a `RoomCubit`
with `post()`.

**Done when:** new test + `test/features/beacon_threads/` + `test/features/beacon_view/` green.

### R1b — `BeaconRoomSurface(host:)` and widget gating

**Goal:** plan §5.3, widget side.

**Files**
- `BeaconRoomSurface` (`beacon_room_surface.dart:21,31,135-187`): take `RoomHost host` instead of
  `BeaconViewCubit beaconViewCubit`; rebuild on `host.changes` with a `StreamBuilder`.
- pass `host.capabilities` to `ThreadDetail` → `BeaconRoomBody` → `RoomMessageTile`.
- gate `BeaconRoomBody` actions (:640 Turn into, :650 Child request, :663-668 Update plan, :687
  Jump to plan, :709 Pin fact, :726 View pinned fact) and the header `_PinnedNowRow` (:235-240).
- gate `RoomMessageTile` commitment sheet (:2698), child promotion footer (:1572/:1578), fact
  history (:584/:953), closure story card (:481-482).
- update the test files that pass `beaconViewCubit:` (`grep -rln "beaconViewCubit:"
  packages/client/test`) to pass `host:`.
- create `packages/client/test/features/beacon_threads/room_capabilities_widget_test.dart`

**Tests (write first, widget, `support/room_body_harness.dart`):** with `post()` the message actions
sheet shows none of the six Request items and no pinned NOW row; with `request()` it shows them.

**Done when:** new test + `test/features/beacon_threads/` + `test/features/beacon_view/` +
`test/ui/widget/` green.

### S5 — Kind-aware creation

**Goal:** plan §4.1 (title barrier) and §4.11 first bullet. A Post draft with empty content can be
created end-to-end; Requests unchanged.

**Files**
- `packages/server/lib/data/database/common_fields.dart` `BeaconTitleDescriptionFields`: title
  `withLength(min: 0, max: kBeaconTitleMaxLength)` (beacons only; leave other mixins alone).
- `packages/server/lib/domain/policy/beacon_creation_policy.dart` (:6-81): add `BeaconKind kind` to
  the entry points used by create, draft save, publish and edit (find callers: `grep -rn
  "BeaconCreationPolicy\.\|normalizeStandaloneDescription" packages/server/lib`). Request branch:
  today's code plus "title required" (`title.trim().length >= kTitleMinLength`, same message the
  GraphQL layer gives today), so the Drift change does not weaken Requests. Post branch: title and
  description must be empty; no needs/slug/schedule/cover; `isDiscoverable == false`; no parent.
- `packages/server/lib/domain/port/beacon_repository_port.dart` (:12) and its implementation and
  mock: `createBeacon` takes `kind` and `forwardPolicy`.
- `BeaconCase.create` (`beacon_case.dart:197`), `updateDraft` (:287), `publishDraft` (:269), `update`
  (:334): pass the kind; a Post is created only as a draft.
- `mutation_beacon.dart` `beaconCreate` (:71-108): new optional args `kind: Int`, `forwardPolicy:
  Int`; the title arg becomes nullable (today `InputFieldBeaconTitle.fieldNonNullable`, :75); the
  resolver rejects a missing title for `kind != 1` with the same error as before.
- tests: `test/domain/policy/beacon_creation_policy_kind_test.dart`,
  `test/api/controllers/graphql/mutation_beacon_create_kind_pg_test.dart` (tag `pg`: real GraphQL →
  real repository)

**Tests (write first)**
- policy: Post with empty fields passes; Post with title / description / need / schedule /
  discoverable / parent throws; Request with empty title throws "title required"; Request with empty
  description still throws "Description is required".
- GraphQL → DB: `beaconCreate(kind: 1, forwardPolicy: 0)` without a title stores `kind 1,
  forward_policy 0, status 3, title ''`; `beaconCreate(kind: 1, title: "x")` errors; `beaconCreate`
  without `kind` and without a title errors as today; with a title behaves as today.

**Done when:** in REQUIRED mode the two new files plus the existing beacon create tests
(`grep -rln "beaconCreate\|BeaconCase(" packages/server/test`) are green.

### S4a — Forward policy on forward and invite paths; `beaconForwardingOpen`

**Goal:** plan §4.3.

**Files**
- create `packages/server/lib/domain/policy/beacon_forward_policy.dart`:
  `static bool canForward({required BeaconEntity beacon, required String senderId}) =>
  beacon.allowsForward && (beacon.forwardPolicy == BeaconForwardPolicyValue.open || senderId ==
  beacon.author.id);`
- `ForwardCase` (in the shared check method from S11a): replace the `allowsForward` check with
  `canForward`; `!allowsForward` keeps today's exception and message; closed Post →
  `UnauthorizedException('Forwarding is off for this post')`.
- `InvitationCase.create` (:75-79), `accept` (:234-260, no check today — add one before
  `bindMutual`), `_acceptBeaconInviteOnly` (:374-378): `canForward` with the invite **issuer** as
  sender; for a Post, take `lockForPostMutation` first and check under it.
- the invited-user creation paths that end in `_materializeBeaconInviteForward`
  (`user_repository.dart` ~:244, ~:412; callers: `grep -rn "createInvited" packages/server/lib/domain`):
  check `canForward` (and lock for Posts) before calling.
- `BeaconCase.openForwarding(authorId, id)` + V2 mutation `beaconForwardingOpen(id: String!):
  Boolean` in `mutation_beacon.dart`: lock; author only; `kind post`, `status open`,
  `forward_policy 0` → 1; otherwise throw (`UnauthorizedException` non-author,
  `BeaconCreateException` wrong kind/state).
- tests: `test/domain/policy/beacon_forward_policy_test.dart`,
  `test/domain/use_case/forward_case_post_policy_test.dart`,
  `test/domain/use_case/invitation_case_post_policy_test.dart`,
  `test/api/controllers/graphql/mutation_beacon_forwarding_open_test.dart`

**Tests (write first)**
- policy truth table: Request open → anyone; Post open → anyone; Post closed → author only; not
  open family → nobody.
- ForwardCase: non-author forwarding a closed Post throws; author succeeds; Requests unchanged
  (`forward_case_test.dart` green).
- InvitationCase: invite creation on a closed Post by a non-author fails; accepting a non-author's
  invite to a closed Post creates no edge; the author's invite works; accepting an invite to a
  Request that is no longer open now fails (new for both kinds — say so in the commit message).
- `beaconForwardingOpen`: author 0 → 1; second call errors; non-author and Request rejected.

**Done when:** new tests + `forward_case_test.dart`, `forward_case_auth_test.dart`,
`invitation_case_test.dart` green.

### S4b — `viewer_can_forward` and Hasura columns (m0211)

**Goal:** plan §4.3 read model; §4.11 Hasura exposure.

**Files**
- create `m0211.dart`: `CREATE FUNCTION public.beacon_get_viewer_can_forward(beacon_row
  public.beacon, hasura_session json) RETURNS boolean LANGUAGE sql STABLE` = `beacon_row.status IN
  (0, 7, 8) AND (beacon_row.forward_policy = 1 OR beacon_row.user_id = (hasura_session ->>
  'x-hasura-user-id'))` — copy the session claim expression from `beacon_get_is_pinned`.
- `hasura/metadata.json`: computed field `viewer_can_forward` on `beacon` and in the role `user`
  select permission; columns `kind`, `forward_policy`, `last_activity_at`, `post_root_message_id` in
  that permission; `pinned_at` in the `beacon_pinned` select permission.
- tests: `test/data/database/m0211_viewer_can_forward_pg_test.dart`,
  `test/data/database/m0211_hasura_metadata_test.dart` (shape),
  `test/api/post_hasura_read_pg_test.dart` (behaviour, `IsolatedHasuraSession`)

**Tests (write first)**
- pg: the SQL function matches `BeaconForwardPolicy.canForward` for the four truth-table cases.
- shape: the permission lists the four columns and the computed field.
- behaviour: as role `user`, a recipient of a closed Post reads `viewer_can_forward false`, the
  author `true`; `kind`, `forward_policy`, `last_activity_at` are selectable;
  `assertMetadataConsistent()` passes.

**Done when:** in REQUIRED mode the three files and `test/api/beacon_access_hasura_test.dart` are
green.

### S6 — `postPublish`

**Goal:** plan §4.5.

**Files**
- create `packages/server/lib/domain/use_case/post_case.dart` (`@Singleton()`), method
  `Future<PostPublishResult> publish({required String authorId, required String beaconId, required
  String body, required List<String> mentionUserIds, required List<int> mentionOffsets, required
  List<int> mentionLengths, required List<String> recipientIds, required Map<String, String> notes,
  required BeaconForwardPolicyValue forwardPolicy, Stream<Uint8List>? attachmentBytes, String?
  attachmentFilename, String? attachmentMimeType})`. Map `recipientIds`/`notes` onto the existing
  `ForwardCase.forward` parameters (read its signature, `forward_case.dart:160`); map the three
  mention lists and the attachment onto `BeaconRoomCase.createMessage` (`beacon_room_case.dart:299-312`).
- `lib/domain/entity/post_publish_result.dart`: `{beaconId, rootMessageId}`.
- `BeaconRoomCase.createMessage`: new optional `Set<String> suppressMentionNotifyFor` (only
  `PostCase` passes it) that drops mention intents for those users (R4-6). Default empty ⇒ no
  behaviour change.
- beacon repository port + implementation: `setPostRootMessage(beaconId, messageId)` = `UPDATE
  beacon SET post_root_message_id = $2 WHERE id = $1 AND post_root_message_id IS NULL`, and
  `setForwardPolicy(beaconId, policy)`.
- V2 mutation `postPublish` in new `mutation/mutation_post.dart` (register it): args `id`, `body`,
  `mentionUserIds`, `mentionOffsets`, `mentionLengths`, `recipientIds`, `notes` (the same note input
  shape `beaconForward` uses — copy it), `forwardPolicy`, and the attachment upload argument exactly
  as `roomMessageCreate` declares it in `mutation_beacon_room.dart`. Returns `{beaconId,
  rootMessageId}`.
- tests: `test/domain/use_case/post_case_publish_pg_test.dart` (pg, real dispatch),
  `test/api/controllers/graphql/mutation_post_publish_test.dart`

**Steps** (all inside `attention.runAction(actorUserId: authorId, …)`)
1. `lockForPostMutation(beaconId)`; re-read the beacon.
2. Require author and `kind == post`; otherwise throw (`UnauthorizedException` /
   `BeaconCreateException`).
3. If `status == open && postRootMessageId != null` → return the existing ids (idempotent retry).
4. Require `status == draft`, `recipientIds.isNotEmpty`, `body.trim().isNotEmpty ||
   attachmentBytes != null`.
5. `setForwardPolicy`; publish through the code path `BeaconCase.publishDraft` uses.
6. Forward through `ForwardCase` (its Post branch runs all checks under the lock, S11a).
7. `createMessage(… suppressMentionNotifyFor: recipientIds.toSet())`; `setPostRootMessage`.

**Tests (write first)**
- happy path: two recipients → status 0, policy stored, two edges, two admitted addressees, one
  root message with the given mention spans, `post_root_message_id` set, one `relayReceived` receipt
  per recipient, no mention receipt for a mentioned recipient, per-recipient notes stored.
- photo-only: empty body + one attachment → a root with one attachment.
- empty body, no attachment → fails, nothing written.
- recipient not mutually visible → whole call fails; still a draft, no edges, no message.
- retry by the author after success → same ids, nothing new written.
- retry by a non-author on the published Post → rejected, nothing written.
- calling on a Request draft, or on a converted Request (set `kind 0` directly) → rejected.
- mutation test: arguments parsed and passed to a fake `PostCase`.

**Done when:** in REQUIRED mode both files and `forward_case_test.dart`,
`beacon_room_case_message_mutations_test.dart` are green.

### S11b — Concurrency: publish ∥ block, cancel ∥ cancel, invite accept ∥ block

**Files:** extend `post_lock_order_pg_test.dart`.

**Tests (write first, pg)** — 20 rounds each, no `40P01`, each round < 10 s:
- `postPublish` to B ∥ B blocks A ⇒ either publish failed, or it succeeded and B's edge is cancelled
  by the block.
- two inbound edges to B, both cancelled in parallel ⇒ B ends at `room_access 0`.
- invite accept by B for A's Post ∥ B blocks A ⇒ no deadlock; no admitted row survives the block.

**Done when:** the file is green three runs in a row in REQUIRED mode.

### S3a — Request-only guards in use cases; room-mutation table

**Goal:** plan §4.9 (Dart part).

**Files**
- create `packages/server/lib/domain/policy/beacon_kind_policy.dart`:
  `static void requireRequest(BeaconEntity b) { if (b.kind != BeaconKind.request) throw const BeaconNotRequestException(); }`
- `BeaconNotRequestException` in `exception.dart`, code `beaconNotRequest` appended to
  `BeaconExceptionCode`.
- call it right after the beacon is loaded in: `HelpOfferCase.offerHelp` (:102), `setRoleLabel`
  (:218), `withdraw` (:288); `CoordinationCase._prepareAdmissionAction` (:133), `releaseCommitment`
  (:511), `setCoordinationResponse` (:607), `setBeaconStatus` (:687), `helpOffersWithCoordination`
  (:112); `ClosureCase._requireAuthor` (:102) and every other public `ClosureCase` method that loads
  the beacon (read the file; list them in the commit message); `BeaconCase.beaconCancel` (:767),
  `fork` (:698); `BeaconChildCreateCase._assertParentCreateAllowed` (:475, parent);
  `BeaconDisplayCase.displayStatuses` (:53 — **skip** Posts, return no entry for them).
- room mutations: list every mutation in `MutationBeaconRoom.all` (`mutation_beacon_room.dart`).
  Post-allowed: create/edit/delete own message, reactions, attachments, polls, seen/read marks,
  thread listing. Everything else (participant offer help, room admit, steward promote, now-line
  update, plan update, coordination items, fact cards `beacon_fact_card_case.dart:55`, child
  promotion, …) calls `requireRequest` in its use case. Note: after conversion the beacon is a
  Request, so role-6 offers (S12b) are allowed.
- tests: `test/domain/policy/beacon_kind_policy_test.dart`,
  `test/api/controllers/graphql/beacon_room_mutation_kind_table_test.dart`,
  `test/domain/use_case/request_only_guards_test.dart` (mockito; one case per guarded method)

**Tests (write first)**
- policy: Post throws `BeaconNotRequestException`; Request passes.
- table test: a const map `{mutationName: postAllowed}` must contain exactly the names in
  `MutationBeaconRoom.all` (fails when someone adds a mutation without classifying it).
- guards: each guarded method called with a Post entity throws `BeaconNotRequestException` before
  any write port is called (verify no interactions on the write mocks).

**Done when:** the three files and all existing `test/domain/use_case/` tests are green.

### S3b — DB help-offer guard (m0212) and Hasura help-offer kind check

**Files**
- create `m0212.dart`: `CREATE FUNCTION public.beacon_help_offer_request_only()` raising
  `check_violation` when the beacon has `kind = 1`; `BEFORE INSERT ON public.beacon_help_offer FOR
  EACH ROW` trigger.
- `hasura/metadata.json`: `beacon_help_offer` insert check (~:1553) and update check (~:1628) gain
  `{"beacon": {"kind": {"_eq": 0}}}` inside their `_and`.
- tests: `test/data/database/m0212_help_offer_guard_pg_test.dart`,
  `test/data/database/m0212_hasura_help_offer_kind_test.dart` (shape),
  `test/api/help_offer_post_hasura_pg_test.dart` (behaviour)

**Tests (write first):** direct SQL insert for a Post raises, for a Request succeeds; shape test;
as role `user`, inserting a help offer for the Post is rejected and for the Request accepted;
`assertMetadataConsistent()` passes.

**Done when:** in REQUIRED mode the three files are green.

### S3c — Request-only SQL exclusions (m0213)

**Files**
- create `m0213.dart`: `CREATE OR REPLACE` of `responsibility_scope_base_beacons`
  (`m0193.dart:4105-4120`) with `kind = 0`, and of `beacon_apply_inbox_before_response_tombstone`
  (`:510-606`) acting only for `kind = 0`. Copy each definition exactly first, then add the filter.
- repository SQL: `constellation_field_repository.dart:177,207` and
  `constellation_field_snapshot_reader.dart:509,549` (Request sections only), `beacon_repository.dart:59,79`
  (deadline reminder), `closure_reminder_repository.dart:92` (stale-request reminder); read
  `attention_repository.dart:1027,1075` and add `kind = 0` only if the query feeds a Request-only
  surface — write the decision as a one-line comment there.
- test: `test/data/database/m0213_request_only_sql_pg_test.dart`

**Tests (write first, pg):** for a Post and a Request with the same author/recipients: the Post is
absent from `responsibility_scope_base_beacons`, the constellation Request section, deadline
reminder candidates, stale-request candidates; deleting the Post creates no before-response
tombstone; the Request appears in all of them as before.

**Done when:** in REQUIRED mode the test and the existing tests of the touched repositories are
green.

### S3d — Request-only audit

**Files:** `test/domain/use_case/post_request_only_audit_pg_test.dart` (pg, real repositories).

**Tests:** seed one Post (via `postPublish`) and one Request with the same author and two
recipients. Assert the Post is absent from every list in S3c, `BeaconDisplayCase` output, and has no
`beacon_closure` row; that `HelpOfferCase.offerHelp`, `CoordinationCase.acceptHelpOffer`,
`ClosureCase.close`, `BeaconCase.beaconCancel`, `BeaconCase.fork`,
`BeaconChildCreateCase.createChild` (parent = Post) throw `BeaconNotRequestException`; and that the
Post is present in the recipients' `inbox_item`, `beacon_member`, the room message list, attention
receipts and `BeaconForwardGraphCase.asMap` for a recipient.

**Done when:** in REQUIRED mode the test is green.

### S8 — Block-aware Post room gate

**Goal:** plan §4.7.

**Files**
- `BeaconRoomCase._canUseRoom` (`beacon_room_case.dart:125-137`): for a Post also require
  `canReadContent` (the guard `ForwardCase` uses at :208). Check that every room read/write entry
  point goes through `_canUseRoom` (list messages :529, attachments, participants, reactions, seen,
  polls); add the call where it is missing for Posts.
- `hasura/metadata.json`: in the `beacon_participant` select permission branch admitting
  `room_access = 3` (~:1705), and in any other room-table permission with the same branch (search
  `"room_access"`), add `{"_or": [{"beacon": {"kind": {"_eq": 0}}}, {"beacon": {"can_read_content":
  {"_eq": true}}}]}` — Requests unchanged.
- tests: `test/domain/use_case/post_room_block_gate_pg_test.dart`,
  `test/data/database/post_room_hasura_shape_test.dart`, `test/api/post_room_block_hasura_pg_test.dart`

**Tests (write first)**
- A authors a Post, F forwards it to R, R admitted. A blocks R ⇒ R's `listMessages`,
  `createMessage`, `reactionToggle` throw the room-access exception; F still works. R blocks A ⇒ same.
- a Request room under the same blocks behaves exactly as today (copy one existing Request room
  access test case).
- shape: every matching branch has the kind-scoped predicate.
- Hasura behaviour: after the block, R selecting the Post's `beacon_participant` rows gets none; F
  gets them; for a Request R's result is unchanged; `assertMetadataConsistent()` passes.

**Done when:** in REQUIRED mode the three files are green.

### S9 — `postLeave` / `postReturn`

**Goal:** plan §4.8.

**Files**
- `PostCase.leave(userId, beaconId)` / `PostCase.returnTo(userId, beaconId)`: lock first; the
  viewer's participant row must have `role = 6` (Post, or Request converted from a Post); leave:
  `inbox_item.status = 2` (keeps `contact_inbox_on_decline`), `room_access = 5`; return: inbox
  status 1, `room_access = 0`, then `SELECT post_reconcile_admission(beaconId, userId)`. Author or
  non-addressee → `UnauthorizedException`. For a converted Request `post_reconcile_admission`
  returns early (kind 0): return then sets `room_access = 3` directly.
- V2 mutations `postLeave(id)`, `postReturn(id)` in `mutation_post.dart`.
- `hasura/metadata.json`: `inbox_item` update permission (role `user`) gains `{"beacon": {"kind":
  {"_eq": 0}}}`.
- tests: `test/domain/use_case/post_leave_return_pg_test.dart`,
  `test/data/database/post_inbox_hasura_shape_test.dart`,
  `test/api/post_inbox_hasura_pg_test.dart`; add "forward to B ∥ B leaves" (20 rounds, no `40P01`)
  to `post_lock_order_pg_test.dart`.

**Tests (write first)**
- leave ⇒ inbox 2, access 5; the pending inbound contact edge is declined; B's `createMessage` is
  rejected by the room gate.
- return with an active edge ⇒ 3; without ⇒ 0. Left, then new edge D → B ⇒ 5; then return ⇒ 3.
- author leave ⇒ rejected.
- Hasura: as role `user`, updating the inbox status of a Post row is rejected; of a Request row
  accepted; `assertMetadataConsistent()` passes.

**Done when:** in REQUIRED mode the files are green.

### S7 — First-response claim, `postFirstResponse`, contract (m0214)

**Goal:** plan §4.4 and §5.6 events.

**Files**
- create `m0214.dart`:
  - `CREATE TABLE public.post_first_response (beacon_id text NOT NULL REFERENCES public.beacon(id)
    ON DELETE CASCADE, user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
    source_kind smallint NOT NULL CHECK (source_kind IN (1, 2)), source_id text NOT NULL, created_at
    timestamptz NOT NULL DEFAULT now(), PRIMARY KEY (beacon_id, user_id));`
  - `CREATE FUNCTION public.post_claim_first_response(p_beacon text, p_user text, p_kind smallint,
    p_source text) RETURNS boolean`: false unless `kind = 1` and `user_id <> p_user`; `INSERT … ON
    CONFLICT DO NOTHING`; `GET DIAGNOSTICS _n = ROW_COUNT`; if `_n = 1` then `PERFORM
    public.contact_engage(p_beacon, p_user); RETURN true;` else `RETURN false`.
- account erasure: add `post_first_response` where account data is erased (follow what was done for
  closure tables: `grep -rn "beacon_closure" packages/server/lib/data/repository | grep -i eras`).
- beacon room repository port + implementation: `claimPostFirstResponse(beaconId, userId, kind,
  sourceId) → bool`; `toggleReaction` (`beacon_room_repository.dart:1241-1269`) returns `bool added`
  (update port, mock, callers).
- `BeaconRoomCase.createMessage` (:299-478): for a Post always persist inside `runAction` (also
  when `!hasDirected`, :471-473); after the insert, for non-author actors, claim (kind 1); if true
  record `postFirstResponse` for the author.
- `BeaconRoomCase.reactionToggle` (:1083-1112): run inside `runAction`; when `added`, the beacon is a
  Post and the actor is not the author, claim (kind 2); if true record `postFirstResponse`.
- `AttentionEventType.postFirstResponse` (`attention_models.dart:60-98`), `assertDeclared` (:23-57),
  every exhaustive switch in `attention_policy.dart` (:60, :119, :155, :206, :265, :279, :334, :368,
  :410; wire name `'post_first_response'`), `AttentionIntentCase.postFirstResponse` modelled on
  `roomMessagePosted` (:321) with recipient = author and reason `postAuthor` (add the reason where
  `directedChatTarget` is enumerated); `NotificationKind.postFirstResponse` and every exhaustive
  switch over `NotificationKind` (fix each compiler error).
- `docs/contracts/updates-event-contract.json`: entries in `eventTypes`, `producers`,
  `eventClassifications` per plan §5.6, `producerTests:
  ["packages/server/test/domain/use_case/post_first_response_pg_test.dart"]`.
- client mirror: `packages/client/lib/domain/attention/attention_event_classification.dart`.
- tests: `test/domain/use_case/post_first_response_pg_test.dart` (pg, real dispatch)

**Tests (write first)**
- B's first message ⇒ one `postFirstResponse` receipt for A and B's inbound contact edge
  `contact_outcome = 1`; B's second message ⇒ nothing new.
- C reacts on the root ⇒ receipt; removes and re-adds ⇒ nothing new.
- B reacts, then writes ⇒ one receipt; claim `source_kind = 2`.
- A's own message/reaction ⇒ no claim; a Request room ⇒ no claim.
- B's message ∥ B's reaction (10 rounds) ⇒ exactly one claim row.
- contract tests: `test/architecture/updates_event_contract_test.dart`,
  `updates_event_coverage_test.dart`, `closure_event_types_contract_test.dart`,
  `test/domain/attention/attention_policy_test.dart`, client
  `test/architecture/updates_event_contract_test.dart`,
  `test/features/inbox/attention_event_classification_test.dart`.

**Done when:** in REQUIRED mode all listed tests are green.

### S10a — Attention projection: kind, root excerpt, image

**Goal:** plan §5.6 projection.

**Files**
- attention SQL that builds receipt rows (`attention_repository.dart`, grouping ~:320-452 and the
  receipt select): add `b.kind`, the root excerpt (`left(m.body, 140)` through
  `post_root_message_id`) and the first root image attachment id.
- `AttentionReceipt` (`attention_models.dart:380`): `beaconKind`, `postRootExcerpt`,
  `postRootImageId`; the GraphQL type for receipts (find where `AttentionReceipt` is mapped to GQL)
  and the client SDL.
- test: `test/data/repository/attention_post_projection_pg_test.dart`

**Tests (write first, pg):** a Post arrival receipt carries `kind 1`, the excerpt and the image id;
a Request receipt carries `kind 0` and nulls; existing receipt fields unchanged (compare one Request
receipt field by field with a snapshot taken before the change in the same test).

**Done when:** in REQUIRED mode the test and `test/data/repository/attention*` are green.

### S10b — Post grouping, position, pinned and dismiss semantics

**Goal:** plan §5.6 server read rule.

**Files**
- `attention_repository.dart` (grouping ~:320-452, relay exclusion :388, `MIN(created_at)` :514,
  child previews :1116) and `attention_dismissible_sql.dart` (:64 pinned predicate, :149 relay
  exclusion, :278 outcome dismissal). First write, as a comment above the grouping query, today's
  rule in three lines. Then introduce **one** kind-aware eligibility SQL fragment used by grouping,
  previews, counts, dismiss-all and sweeps: for `kind = 1` include `relay_received`, position =
  `MAX(created_at)` of the group, Post inbox items are never pinned decisions and never
  outcome-dismissed (clearing a Post row clears its receipts and leaves `inbox_item` and room access
  unchanged; the guard at `m0193.dart:1916` must never be hit for Posts).
- test: `test/data/repository/attention_post_grouping_pg_test.dart`

**Tests (write first, pg)**
- arrival only ⇒ one grouped, non-pinned row; dot/count = 1.
- arrival, then a reply to me an hour later ⇒ one row positioned at the reply time.
- dismiss-all ⇒ the row is gone, `inbox_item.status` unchanged, room access unchanged, the sweep
  reports zero failures.
- after clearing, a new mention ⇒ the row is back.
- a Request decision row is still pinned and dismissed exactly as before (copy an existing case).

**Done when:** in REQUIRED mode the test, `test/data/repository/attention*` and
`test/domain/attention/` are green.

### S10c — In-app mute for Posts

**Goal:** R4-4 (Posts only).

**Files:** the eligibility fragment from S10b gains: for `kind = 1`, hide receipts when the viewer's
account has `notification_beacon_mute` for the beacon with `muted_until IS NULL OR muted_until >
now()`, except receipts whose notification kind is `roomMention` (find the stored column). Requests
are not affected. Test: extend `attention_post_grouping_pg_test.dart` with a `mute` group.

**Tests (write first, pg):** muted Post: arrival and reply rows hidden from list and count; mention
shown; dismiss-all does not clear hidden rows; after expiry (`muted_until` in the past) uncleared
rows are visible again; a muted **Request** still shows its rows exactly as today.

**Done when:** in REQUIRED mode the file is green.

### S12a — `beaconConvertToRequest`

**Goal:** plan §4.6.

**Files**
- `lib/domain/entity/beacon_conversion_content.dart`: title, description, needs, primary need slug,
  `startAt`, `endAt`.
- beacon repository port + implementation: `convertPostToRequest(beaconId, content,
  isDiscoverable)` = **one** `UPDATE beacon SET title=…, description=…, needs=…,
  primary_need_slug=…, start_at=…, end_at=…, kind = 0, forward_policy = 1, is_discoverable = …,
  updated_at = now() WHERE id = $1 AND kind = 1 AND status = 0` (affected rows must be 1). Copy the
  column handling (needs encoding etc.) from the repository update used by `BeaconCase.update`
  (`beacon_repository.dart:408`).
- `BeaconCase.convertToRequest(authorId, beaconId, content, isDiscoverable)`: lock; author; validate
  `content` with the Request branch of `BeaconCreationPolicy`; `convertPostToRequest`; insert the
  system message kind 4 with payload `{"event":"convertedToRequest"}` the way kind 3 `closureStory`
  rows are inserted (`grep -rn "closureStory" packages/server/lib`); emit the beacon realtime change
  like `BeaconCase.update`.
- V2 mutation `beaconConvertToRequest(id, title, description, needs, primaryNeedSlug, startAt, endAt,
  isDiscoverable)` — reuse the input field definitions of `beaconUpdateDraft` in `mutation_beacon.dart`.
- tests: `test/domain/use_case/post_convert_pg_test.dart`; add "forward ∥ convert" (20 rounds, no
  `40P01`) to `post_lock_order_pg_test.dart`.

**Tests (write first, pg)**
- valid content ⇒ `kind 0`, `forward_policy 1`, content written, one kind-4 system message,
  addressees still admitted with role 6, `beacon_admitted_helper` still excludes them.
- empty title ⇒ `BeaconCreateException`; the Post unchanged.
- non-author ⇒ rejected; second convert ⇒ rejected.
- a failure injected after the UPDATE (test hook) ⇒ everything rolled back.

**Done when:** in REQUIRED mode the files are green.

### S12b — Intermediate role-6 server rules

**Goal:** plan §5.9.

**Files**
- `beacon_room_repository.dart` `participantOfferHelp` (:1036): for a `role = 6` row keep
  `room_access` unchanged (today resets to requested).
- `inviteOfferUserToBeaconRoom` (:1121): for a `role = 6` admitted row do not return early where
  that skips recording the offer; record it and keep access.
- `CoordinationCase.acceptHelpOffer` (:331): set `role = 2` for a role-6 row.
- `CoordinationCase.declineHelpOffer` (:378-421) and help-offer withdraw: for a role-6 row keep
  `room_access` (do not revoke).
- test: `test/domain/use_case/post_intermediate_state_pg_test.dart`

**Tests (write first, pg)** on a converted Post: B (role 6) offers via `participantOfferHelp` ⇒
offer exists, B still admitted; via the invite-offer path ⇒ same; author declines ⇒ B admitted,
role 6; B withdraws ⇒ admitted; B offers again and the author accepts ⇒ role 2, B in
`beacon_admitted_helper`; B `postLeave` ⇒ access 5 and B's reads are rejected.

**Done when:** in REQUIRED mode the test and existing coordination/help-offer tests are green.

### S13 — Root delete = Post delete

**Files:** `BeaconRoomCase.deleteMessage` (:1162): if the message is the root of a `kind = 1`
beacon, require the author and call `BeaconCase.deleteById`. Test
`test/domain/use_case/post_root_delete_pg_test.dart`.

**Tests (write first, pg):** author deletes the root ⇒ beacon status 2; a member deletes their own
message ⇒ only it is gone; after conversion deleting the former root ⇒ only the message is gone,
`post_root_message_id` NULL.

**Done when:** in REQUIRED mode the test is green.

### S14 — Notification pipeline for Posts

**Goal:** plan §4.11 notifications.

**Files**
- `BeaconNotificationIntent` (`lib/domain/entity/beacon_notification_intent.dart`): `BeaconKind
  beaconKind` (default request).
- `AttentionIntentCase.relayReceived` (:41-60): new parameter `beaconKind`; `ForwardCase` and
  `PostCase` pass it.
- `beacon_notification_copy_builder.dart` (:28, :138-143): `newRelay` + post ⇒ "`$actor shared a
  post with you`"; `postFirstResponse` ⇒ "`$actor replied to your post`". Russian push copy:
  «‹X› поделился постом с вами», «‹X› откликнулся на ваш пост» unless the mockups give other text.
- `beacon_notification_batch_aggregator.dart:49`: Post batches "`$n posts shared with you`" and
  "`$n replies to your posts`"; the generic fallback for Posts is "`$n post updates`" (Requests keep
  "request updates").
- test: `test/domain/notification/post_notification_pipeline_pg_test.dart` (pg, real dispatch: run
  `postPublish` and a first response, then build the jobs/batches the way the notification job
  does — find the job builder from `beacon_notification_service.dart:40`).

**Tests (write first):** the generated job for a Post arrival has the Post text; a first response
has its text; a batch of two Post arrivals uses the Post batch text; a Request relay still says
"`forwarded a request to you`".

**Done when:** in REQUIRED mode the test and existing copy/aggregator tests are green.

### S15 — `myPosts` query

**Goal:** plan §5.6 «Разговоры».

**Files**
- `PostCase.myPosts(viewerId)` → `List<PostSummary>` (id, author id/name/avatar, root excerpt, last
  message excerpt + time, `lastActivityAt`, viewer `pinnedAt`, viewer `mutedUntil`, unread count,
  `isAuthor`). SQL: Posts with `status 0` where the viewer is the author or has an admitted role-6
  row, `beacon_can_read_content(b.id, viewer)`; unread count from the same source as the room unread
  badge (find it: `grep -rn "unread" packages/server/lib/data/repository/beacon_room_repository.dart`).
- V2 query `myPosts: [PostSummary!]!`.
- test: `test/domain/use_case/post_my_posts_pg_test.dart`

**Tests (write first, pg):** author and addressee both see the Post; a left addressee does not; a
blocked viewer does not; pinned/muted/unread values correct (ordering is the client's job).

**Done when:** in REQUIRED mode the test is green.

### G1a — Field payload: posts, memberWebs, hiddenReachCount

**Goal:** plan §6.2 and §6.1 (pinned records).

**Files**
- `packages/server/lib/domain/entity/constellation_field.dart`: `ConstellationPostRecord` (id,
  authorId, lastActivityAt, rootExcerpt, isPinned, hiddenReachCount) and
  `ConstellationMemberWebRecord` (beaconId, personId, state {forwarded, inside}); `posts` and
  `memberWebs` on `ConstellationFieldSnapshot`.
- port `constellation_field_repository_port.dart` + implementation.
- `constellation_field_snapshot_reader.dart`: after own requests (:85) read posts (author or admitted
  role 6; `status 0`; `beacon_can_read_content`; `last_activity_at > now() - interval '72 hours'` or
  pinned by the viewer); then member webs restricted to `_allVisiblePeerIds` (:402); the rest counted
  into `hiddenReachCount`. `inside` = admitted with a `beacon_room_seen` row; `forwarded` = otherwise
  an active inbound edge recipient; the author is always `inside`. `_pinnedBeaconRecords` (:457):
  carry `kind`.
- GraphQL `custom_types.dart` (:966-993) + mapper `constellation_gql_maps.dart`.
- test: new group `Posts and member webs` in `test/data/repository/constellation_field_repository_pg_test.dart`

**Tests (write first, pg):** addressee sees the Post; unrelated viewer does not; 73 h quiet ⇒ absent
unless pinned; C opened ⇒ inside; D only received ⇒ forwarded; E outside the peer set ⇒ not listed
and counted; blocked author ⇒ absent; pinned record carries the kind.

**Done when:** in REQUIRED mode the file is green.

### G1b — `beaconMemberWebs(id)`

**Files:** query `beaconMemberWebs(id: String!): [ConstellationMemberWeb!]!`: requires
`canReadContent`; admitted helpers for everyone; forward recipients only with `canReadInvolvement`;
same peer-set restriction. Test `test/api/controllers/graphql/query_beacon_member_webs_pg_test.dart`.

**Tests (write first, pg):** on a Request, a content reader without involvement gets helpers only;
an involved viewer also gets forward recipients; a non-reader is rejected.

**Done when:** in REQUIRED mode the test is green.

---

## 4. Client

### C0 — Schema refresh, `Beacon` fields, capability truth table, Request-only queries, flag

**Files**
- refresh `packages/client/lib/data/gql/schema.graphql` (§0.1).
- `consts.dart`: `const kPostsEnabled = false;`
- `lib/data/gql/beacon_model.graphql` (:4-62) and the two variants
  (`features/beacon/data/gql/beacon_model_with_admitted_helpers.graphql`,
  `features/my_work/data/gql/beacon_model_with_help_offer_users.graphql`): add `kind`,
  `forward_policy`, `last_activity_at`, `post_root_message_id`, `viewer_can_forward`.
- `lib/domain/entity/beacon.dart` (:24-93): `kind`, `forwardPolicy`, `lastActivityAt`,
  `postRootMessageId`, `viewerCanForward`; `isRequest`. List **every** getter in the file that
  expresses a Request capability (commit, coordinate, offer help, closure, children, fork, …) and
  make each `isRequest && …`. Reuse a root-package `BeaconKind` if one exists (`ls lib/domain/entity/`
  at the repo root); otherwise create it in the client.
- mappers `lib/data/model/beacon_model.dart:10-62`,
  `features/beacon/data/model/beacon_model_with_admitted_helpers.dart`.
- every place that decides whether to show Forward from `allowsForward` (`grep -rn "allowsForward"
  packages/client/lib`) uses `viewerCanForward`.
- Request-only queries: `my_work_fetch.graphql`, `profile_shared_beacons_fetch.graphql`,
  `beacon_fetch_pinned.graphql` add `kind: {_eq: 0}`; `FavoritesCubit` live path
  (`favorites_cubit.dart:116`) ignores Posts.
- tests: `test/domain/entity/beacon_capabilities_kind_test.dart`,
  `test/features/favorites/favorites_post_filter_test.dart`

**Tests (write first):** capability truth table — for each listed getter, a readable open Request
⇒ today's value, a readable open Post ⇒ false; mapper `kind: 1` ⇒ post; Favorites live pin of a
Post ⇒ not added.

**Done when:** new tests + `test/features/beacon_view/`, `test/features/forward/`,
`test/features/my_work/`, `test/features/favorites/`, `test/features/profile_view/` green.

### R2 — `ForwardTargetProfile`

**Files**
- `features/forward/domain/forward_target_profile.dart`: `enum ForwardTargetProfile { request, post }`
  with `showsBand`, `showsReasons`, `showsLineage`, `showsAttribution`, `showsRequirements`,
  `nudgesOfferHelp`.
- `ForwardCubit`: `state.profile` from `state.beacon.kind`.
- `ForwardRecipientPicker`: gate band (:441, :568-570), reasons (:231, :584, :742, :799), lineage
  (:614, :714), attribution dialog (:197-215), requirements bar.
- `forward_draft_policy.dart:39`: false for Posts.
- test `test/features/forward/forward_target_profile_test.dart`

**Tests (write first):** for a Post beacon: no band strip, no reason chips, no lineage header,
send never opens the attribution dialog, no offer-help nudge; Requests: existing
`forward_recipient_picker_test.dart` unchanged.

**Done when:** new test + `test/features/forward/` green.

### C2a — Kind-aware route host and minimal Post screen

**Goal:** plan §5.4 routing.

**Files**
- `beacon_view_host_screen.dart` (`wrappedRoute` :58-89): before creating providers, resolve the
  beacon kind (new tiny query `beacon_kind_fetch.graphql` `beacon_by_pk(id) { kind }`, cached in a
  small repository). While loading show the existing loading view. Request ⇒ today's providers and
  screen unchanged. Post ⇒ `PostViewCubit`, `ThreadsCubit`, `ThreadHostCubit(capabilities:
  RoomCapabilities.post())` and `PostViewScreen`.
- `features/post_view/ui/bloc/post_view_cubit.dart` `implements RoomHost` (capabilities `post()`):
  loads the beacon through the repository `BeaconViewCubit` uses for the beacon itself only (no
  coordination/closure fetches).
- `features/post_view/ui/screen/post_view_screen.dart`: `BeaconRoomSurface(host: cubit)` and a
  plain app bar with a back button.
- tests: `test/features/post_view/post_view_route_test.dart`

**Tests (write first):** the real route with a Post id and a fake repository whose Request-only
methods (coordination, closure, help offers) **throw** renders `PostViewScreen` with the room; a
Request id renders `BeaconViewScreen` (existing harness `beacon_view_screen_harness.dart`).

**Done when:** new test + `test/features/beacon_view/` green.

### C2b — Post app bar, overflow, pinned strip, root-delete confirm, kind-4 renderer

**Goal:** mockup M4, M11; plan §5.4.

**Files**
- `PostViewScreen` app bar «‹author›: ‹root excerpt›», 🔕 when muted, ⋮: «Участники», «Граф
  пересылок» (`ScreenCubit.showForwardsGraphFor`), «Показать на поле», «Переслать» (if
  `viewerCanForward`), «Разрешить пересылку» (author, closed; M11 confirm dialog →
  `beaconForwardingOpen`), «Удалить пост» (author). Pin/mute/leave/convert come in C5/C6.
- pinned strip `RoomPinnedStrip.postRoot` in the `BasicChatBody` header slot: root excerpt, tap
  scrolls to the root; for a forwarded recipient «Вам переслала ‹X›: «‹note›»».
- root message delete (author) shows a Post-specific confirm («Удалить пост?» per M4) before the
  existing delete.
- `room_message_tile.dart` (~:386 display fallback): render `system_message_kind = 4` as
  «‹author› превратил пост в запрос» (M7); other system kinds unchanged.
- l10n keys.
- tests: `test/features/post_view/post_view_screen_test.dart`,
  `test/features/beacon_threads/room_converted_notice_test.dart`

**Tests (write first):** no tabs/HUD; «Граф пересылок» present; «Переслать» hidden when
`viewerCanForward` false; «Разрешить пересылку» only for the author of a closed Post and calls the
mutation after confirm; deleting the root shows «Удалить пост?»; a kind-4 system message renders
the M7 text.

**Done when:** new tests + `test/features/beacon_threads/` green.

### C2c — Participants screen

**Files:** `features/post_view/ui/screen/post_participants_screen.dart` (side sheet on wide layouts):
«В РАЗГОВОРЕ · n» (admitted members, «автор», «в контактах», «[+ В контакты]» → existing
`ProfileViewCubit.addFriend`, «позвал(а) ‹X›» from forward edges), «ЕЩЁ НЕ ОТКРЫЛИ · n» (names; no
`beacon_room_seen` row), «Как пост дошёл до людей ›» → forward graph; «Можно пересылать
[↗ Позвать]» row (M5). Data: room participants (existing fetch) + seen state (add to the
participants query if missing). Test `test/features/post_view/post_participants_test.dart`.

**Tests (write first):** sections and counts; unopened names listed; «[+ В контакты]» calls
`addFriend`; tapping a person opens the profile.

**Done when:** test green.

### C1 — Post create screen

**Goal:** plan §5.2, mockup M3.

**Files**
- `BeaconSaveCommand` (`lib/domain/use_case/beacon_create_case.dart:14`) and `beacon_create.graphql`:
  `kind`, `forwardPolicy`; for a Post the payload sends no title (not `"Draft"`, today's substitute
  at `beacon_create_cubit.dart:231`) and `isDiscoverable: false` (state default is true at
  `beacon_create_state.dart:84`).
- `BeaconCreateCubit(kind)`; `publishPost({body, mentions, forwardCubit, forwardPolicy,
  attachments})`: `postPublish` (new `post_publish.graphql`, first attachment inline, mentions from
  `CommittedMention` `{userId, start, end}` → ids/offsets/lengths), then the remaining attachments
  via the existing room attachment add (`grep -rn "AttachmentAdd" packages/client/lib`); a failed
  attachment upload retries only that upload and never re-sends `postPublish`.
- `features/beacon_create/ui/screen/post_create_screen.dart` (`@RoutePage()`, `/post/new`,
  `kPathPostNew`, query `forwardToUserId`): M3 layout — «✕ Новый пост», «Кому: …» (opens
  `ForwardRecipientPicker(embedded: true)` on the same `ForwardCubit`), «Можно пересылать» switch
  (on), empty hint, `BasicChatBody` composer with attachments and mentions; ➤ disabled without
  recipients or without text and attachment.
- close: untouched → no server call; with content → «Удалить черновик?» → delete the draft.
- entry points behind `kPostsEnabled`: Activity top bar ✎ (`inbox_screen.dart:119-135`), My Work
  «+» menu (Пост / Запрос).
- l10n; tests `test/features/beacon_create/post_create_cubit_test.dart`,
  `test/features/beacon_create/post_create_screen_test.dart`

**Tests (write first):** `ensureDraft` for a Post sends `kind 1`, no title, not discoverable;
`publishPost` calls `postPublish` once with the mapped mention lists, recipients, notes, policy and
the first attachment, then uploads the rest; a failed second upload retries only that upload; a
network error on `postPublish` lets the user retry with identical arguments; ➤ disabled states;
close dialogs; entry points hidden while `kPostsEnabled` is false.

**Done when:** tests green.

### C3 — «Для вас» Post row

**Files:** client receipt fragment + mapper gain `beaconKind`, `postRootExcerpt`, `postRootImageId`
(S10a); `activity_stream_view.dart` (`_ActivityStreamCell` :992-1073) renders
`features/inbox/ui/widget/post_attention_row.dart` for Post groups (M1 variants: arrival, reply,
mention, first responses «На ваш пост откликнулись …»). Test
`test/features/inbox/post_attention_row_test.dart`.

**Tests (write first):** **fetch → row**: a fake GraphQL response in the real fragment's JSON shape
for a Post group maps and renders the right M1 variant; a Request group still renders
`RequestAttentionCard`; tap navigates to `/beacon/view/<id>`.

**Done when:** test + `test/features/inbox/` + `test/domain/attention/` green.

### C4 — «Разговоры» tab

**Files:** `InboxScreen` (`inbox_screen.dart:21,119-142`): `TenturaPrimaryTabBar` «Для вас» |
«Разговоры» (like `friends_screen.dart:168`); default «Для вас»; reselecting the nav item returns
to it. `features/inbox/data/gql/my_posts.graphql` (S15) + `PostsCubit` (injected clock) +
`PostsTabView`: pinned first by `pinnedAt`, then by `lastActivityAt`, split at 72 h into «Сейчас» /
«Затихли»; 🔕; unread counts; no tab dot; refetch after reply/pin/mute/leave (listen to the existing
realtime beacon change stream). Test `test/features/inbox/posts_tab_test.dart`.

**Tests (write first):** ordering, the 72 h split with a fixed clock, muted icon, M2 empty state,
refetch on a pin event.

**Done when:** test green.

### C5 — Mute, pin, leave/return UI

**Files:** ⋮ «Заглушить ›» → 1 ч / 3 ч / день / 3 дня / навсегда, «Включить звук» when muted →
`beaconMuteSet` / `beaconMuteClear` (new `.graphql`, `PostMuteRepository`); «Закрепить в
разговорах» / «Открепить» → existing favorites pin/unpin repository; «Выйти из разговора»
(recipient) → confirm (M10) → `postLeave`; the «Не интересно» archive
(`inbox_rejected_screen.dart:93`) uses `postReturn` for Post rows instead of `unreject`. Test
`test/features/post_view/post_mute_pin_leave_test.dart`.

**Tests (write first):** each duration sends the expected `mutedUntil` (fixed clock); forever ⇒
null; pin/unpin call the favorites repository; leave calls `postLeave` after confirm; the author
sees no «Выйти»; «Вернуть» on a Post row calls `postReturn`, on a Request row `unreject`.

**Done when:** test green.

### C6 — Convert to Request

**Files:** ⋮ «Превратить в запрос» (author) → M7 dialog → `BeaconCreateRoute(convertFromPostId:)`
(new query param, `beacon_create_screen.dart:51-56`); `BeaconCreateCubit.loadConvertFromPost`:
prefill title (first line, cut to the form's title max), description (rest), cover suggestion (first
image); no draft is saved; submit calls `beaconConvertToRequest` (new `.graphql`) with the form
content and the dialog's discoverability; if the author kept the photo, then set the cover with the
existing cover upload; on success open `/beacon/view/<id>`; cancel ⇒ no server call. Test
`test/features/beacon_create/convert_from_post_test.dart`.

**Tests (write first):** prefill rules (multi-line, long first line cut, photo-only root ⇒ empty
title and the form's title-required error); submit sends one convert call; a cover upload failure
still opens the Request; cancel sends nothing.

**Done when:** test green.

### C7 — Intermediate participant state UI

**Files:** participant model gains `role` if missing (check `fetchParticipants`); `BeaconViewScreen`
shows the M8 «Участник из поста» card for a role-6 viewer with [Предложить помощь] (existing offer
flow) and «Выйти из чата» (`postLeave`); the author's People tab gets «ИЗ ПОСТА». Test
`test/features/beacon_view/post_origin_participant_test.dart`.

**Tests (write first):** role-6 viewer sees the card and both actions; a helper does not; the
author sees the section with role-6 people.

**Done when:** test + `test/features/beacon_view/` green.

### K1 — `RadiusRecipientSelection` (pure)

**Files:** `features/constellation/domain/radius_recipient_selection.dart`; test
`test/features/constellation/radius_recipient_selection_test.dart`.

**Model:** immutable; `center`, `radius`, `positions: Map<String, Offset>`, `eligible`,
`manualAdded`, `manualRemoved`. `selected` = (`{p : |pos − center| ≤ radius}` ∪ `manualAdded`) \
`manualRemoved`, ∩ `eligible`. `toggle(id)`: if selected → add to removed, drop from added; else add
to added, drop from removed. `withRadius`, `withCenter`. `static double startRadius(center,
positions, eligible)` = distance to the 3rd-nearest eligible × 1.1 (fewer than 3 ⇒ farthest × 1.1;
none ⇒ `kComposerMinRadius`).

**Tests (write first):** manual add survives shrinking; manual remove survives growing; ineligible
never selected; `startRadius` covers exactly 3 of 5; toggle twice restores.

**Done when:** test green.

### G2b — Client field entities and Post projection

**Goal:** plan §6.1, §6.3.

**Files**
- client field entities and query: `posts`, `memberWebs`, `hiddenReachCount`.
- rename `FieldRequestNode` → `FieldBeaconNode` (`node_details.dart:309-349`) with `kind`; label =
  root excerpt for Posts (`:325` uses the title today); a Post glyph; no status marker.
- composition (`constellation_anchor_composition.dart:146-262`, holders :193-198, drawn ids and
  labels), caps, anchors and node construction consume Requests **and** Posts as one Beacon list.
- `computeConstellationPlacedLayout` (`constellation_layout.dart:219-443`): after the request pass
  (:411-432), an unanchored Post goes to the barycenter of its placed members (author included),
  then `_chooseAutomaticPosition` (:517). An anchored, expired Post is dormant like a pinned closed
  Request.
- tests: `test/features/constellation/constellation_post_projection_test.dart`

**Tests (write first):** field payload → composition → scene: a Post appears with its excerpt
label and glyph; lands within one candidate step of its members' barycenter; an expired unpinned
Post is absent; an expired pinned Post is dormant; Requests unchanged (existing layout tests).

**Done when:** new test + `test/features/constellation/` green.

### G2c — Post webs, fade, «+N»

**Files:** `ConstellationEdgeKind` + `webForwarded`, `webInside`, `draftRecipient`
(`constellation_cubit.dart:33`); styles (`constellation_edge_style.dart:7-44`); legend
(`graph_legend_content.dart:104-125`); in `_rebuildGraph` (:2093-2312) star edges from the
**selected** Post to its placed members, by semantic id (G2a); fade = 1 until 48 h, linear to 0.25 at
72 h (`lastActivityAt` vs `loadedAt`); «+N» chip (`constellation_overflow_group.dart`) where N =
`hiddenReachCount` + visible members not placed because of the render cap. Test
`test/features/constellation/constellation_post_webs_test.dart`.

**Tests (write first):** webs only while selected; a web and a trust path on the same pair both
drawn; fade at 24 h / 60 h / 72 h; «+3» for `hiddenReachCount 2` plus one capped member.

**Done when:** new test + `test/features/constellation/` green.

### G3 — Request webs on selection

**Files:** `beacon_member_webs.graphql`; `ConstellationCubit.selectRequest` (:1234) fetches lazily,
caches per id, adds webs. Test `test/features/constellation/constellation_request_webs_test.dart`.

**Tests (write first):** select ⇒ one fetch, webs drawn; deselect ⇒ removed; reselect ⇒ cached.

**Done when:** test green.

### K2a — Composer cubit: draft lifecycle and selection adapter

**Files**
- `ForwardCubit.setSelection(Set<String> ids)` next to `toggleSelection` (:464): replaces the
  selected set, keeps notes for ids that stay.
- `features/constellation/ui/bloc/constellation_composer_cubit.dart`: holds
  `RadiusRecipientSelection`, draft position, kind, a `BeaconCreateCubit(kind)` and a
  `ForwardCubit(embedded: true)` created when the server draft exists. Intents: `start(kind,
  scenePos)`, `moveDraft`, `setRadius`, `toggle(personId)` (graph and list), `cancel()`. The server
  draft is created on the first content edit or recipient change; untouched cancel ⇒ no server call;
  touched cancel ⇒ delete the draft; results of async calls that complete after cancel are ignored.
  After every intent push `selection.selected` into `ForwardCubit.setSelection`.
- test `test/features/constellation/constellation_composer_cubit_test.dart`

**Tests (write first):** start ⇒ radius = `startRadius`, 3 selected and pushed; toggle selected ⇒
removed in both; grow radius ⇒ more selected, the removed stays removed; list toggle routed through
`toggle` behaves the same; untouched cancel ⇒ zero server calls; touched cancel ⇒ one delete; a
draft creation that completes after cancel ⇒ deleted, no state change.

**Done when:** test green.

### K2b — Composing phase on the graph

**Files:** `ConstellationPlacementPhase.composing` (`constellation_state.dart:20`); the draft node
`fd:draft` as a **new** topology node positioned by a presentation override (add a method next to
`beginDragNew` :513 that creates the override for a node not yet in the anchor set — `beginDragNew`
itself expects an existing target); widened composition via an optional `extraKeptPeerIds` on
`composeConstellationPresentation` (= forward candidates ∩ field peers); draft edges
(`draftRecipient`) from `fd:draft` to selected people with `reconcileTopology(requestLayout: false,
layoutOnTopologyChange: false)`; in composing, person tap ⇒ `toggle`, person drag-to-pin disabled.
Test `test/features/constellation/constellation_composing_phase_test.dart`.

**Tests (write first):** entering composing adds `fd:draft` and the widened peers without moving
pinned nodes; tap toggles edges; exit restores the composition and removes `fd:draft`.

**Done when:** new test + `test/features/constellation/` green.

### K2c — Radius circle, handle drag, canvas entry

**Files:** wire `canvasBackgroundBuilder` in the `GraphView` setup (`constellation_body.dart:639-786`)
to paint the radius circle and handle; a pointer handler on the handle (hit test within the handle
radius in scene space) that drags the radius live (`setRadius`); entry: app bar «Создать здесь»
(Пост / Запрос) and `onCanvasSecondaryTap` / `onCanvasLongPress` (K0) ⇒ `start(kind, scenePos)`,
with the Post choice behind `kPostsEnabled`. Test
`test/features/constellation/constellation_composer_gestures_test.dart`.

**Tests (write first, widget, real gestures):** secondary tap on empty canvas opens the kind menu
and starts the composer at that point; long press too; dragging the handle outward grows the radius
and selects more people; panning the canvas does not change the radius; with `kPostsEnabled` false
the Post choice is absent.

**Done when:** new test + `test/features/constellation/` green.

### K3a — Composer sheet and list handoff

**Files:** sheet widget (Post: «Получат · n», chips with ×, «Списком ›», «Можно пересылать» on,
attachments row, room composer, ➤; Request: title, short description, «Подробнее», Send); radius
slider (a11y); side panel on wide layouts; «Списком» opens `ForwardRecipientPicker(embedded: true)`
on the composer's `ForwardCubit` with its toggle routed to `ConstellationComposerCubit.toggle` (add
an optional `onToggle` override to the picker). Test
`test/features/constellation/constellation_composer_sheet_test.dart`.

**Tests (write first):** list toggle of a person inside the radius removes them and a later radius
change does not bring them back; chip × removes; slider changes the radius; wide layout shows a
side panel.

**Done when:** test green.

### K3b — Publish, anchor, full-form handoff

**Files:** Post send ⇒ `BeaconCreateCubit.publishPost` (C1) ⇒ `ConstellationAnchorCase.upsert`
(`constellation_anchor_case.dart:248`) with the normalised drop point and the current generation ⇒
field reload ⇒ select the new Post briefly; anchor failure ⇒ snackbar, the Post stays published.
Request send ⇒ `sendRequest` ⇒ anchor ⇒ reload. «Подробнее» ⇒ `BeaconCreateRoute(draftId:)` with the
composer's recipients **and notes** as initial selection (add initial notes to the screen's
`_forwardCubitFor`, `beacon_create_screen.dart:173-194`). Test
`test/features/constellation/constellation_composer_publish_test.dart`.

**Tests (write first):** Post send calls publish once then upserts the anchor with the normalised
point; anchor failure keeps the Post and shows the snackbar; «Подробнее» opens the form with the same
draft id, recipients and notes.

**Done when:** test green.

---

## 5. Docs, release, end-to-end

### D1 — Doc amendments A1–A7

**Files:** `docs/Tentura_current_status_quo.md` (§3–§4: Post), `CONTEXT.md` (Post glossary;
forward ⇒ admission for Posts), `docs/plans/constellation-edge-semantics.md` (D5 :96 membership
webs; D9 :100 composer widening; §9.2 :552 Post presence), `docs/features/beacon_room.md` (Post
admission), `docs/features/constellation.md` (composer), `.cursor/rules/terminology.mdc` («Пост»),
`docs/plans/episode-closure-architecture.md` §Phase B (Post engagement row).

**Done when:** each file contains the amendment (`grep -n "Post\|Пост" <file>`).

### V — Release

**Files:** `consts.dart` `kPostsEnabled = true`; `packages/client/pubspec.yaml` 7.25.0 → 7.26.0;
`packages/client/web/index.html` `?v=7.26.0`; `packages/server/lib/env.dart:79`
`kDefaultMinClientVersion = '7.26.0'`. Do **not** edit the source `web/manifest.json` (see
`AGENTS.md`).

**Checks (all must pass, serially):** the three server suites (§0.2), the client suite, the graph
package suite, both custom-lint runs, `./scripts/check-user-facing-terminology.sh` (add «пост» to
its allowlist if needed), and from `packages/client`: `dart run tool/verify_web_version_consistency.dart`
(sources) — the build-output check runs in CI after `flutter build web`.

### E1 — Web end-to-end journeys

**Prerequisites (must be proven in the run log):** current server built and running, all
migrations applied (`schema_version` = latest), Hasura metadata applied with `is_consistent: true`,
remote schema reloaded, client built from this commit. `scripts/run_client_integration_web_local.sh`
reuses running services, so restart them first.

**Journeys (`packages/client/integration_test/`, follow the existing journeys):**
1. Author A sends a Post to B and C; B replies; A sees «На ваш пост откликнулись» and the reply;
   DB: two edges, B's claim row.
2. B leaves («Выйти из разговора») and returns from «Не интересно»; DB: access 5 then 3.
3. A converts the Post to a Request; B offers help; DB: `kind 0`, B role 6 with an offer.
4. Map composer: A starts on the canvas, removes one person by tap, sends; DB: edges to the
   remaining people, an anchor at the drop point.

**Done when:** the four journeys pass with `scripts/run_client_integration_web_local.sh`.

---

## 6. Review record

Rev 2 applied the Codex (gpt-6.1-sol, high) review of rev 1 (23 findings): per-unit migrations with
upgrade tests (#1); creation through GraphQL/Drift/port/client payload (#2, S5, C1); idempotency
after authorization (#3, S6); photo-only root via inline first attachment (#4, S6); single-UPDATE
conversion with a server-domain command (#5, S12a); eligibility checks under the lock with a barrier
test (#6, S11a); lock coverage for invites, leave/return (locked mutations), convert (#7, S4a, S9,
S11b, S12a); shared kind-aware attention eligibility and Post dismiss semantics (#8, S10b); mute
scoped to Posts, kind-scoped Hasura branch, full client capability truth table (#9, S10c, S8, C0);
real recipient/mention types (#10, S6, C1); role-6 offer branches and real leave (#11, S12b, S9);
RoomHost split and kind-aware route host (#12, R1a, R1b, C2a); receipt projection and fetch→row
test (#13, S10a, C3); `myPosts` instead of Hasura relationships (#14, S15, C4); semantic edge ids
(#15, G2a); unified Beacon projection (#16, G2b); composer split, draft lifecycle, handle gestures,
form handoff with notes, anchor generation (#17, K2a–K3b); notification pipeline (#18, S14); kind-4
renderer and root-delete confirm (#19, C2b); S3 split and client queries only in C0 (#20); REQUIRED
mode, real dispatch in S0, E1 prerequisites (#21, T0); K0 files and pointer-layer enablement (#22);
release checks and the `kPostsEnabled` gate (#23, V, §0.1).

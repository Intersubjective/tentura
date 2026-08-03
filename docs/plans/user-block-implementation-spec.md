---
status: draft
kind: spec
---
# User blocking — implementation specification

**Companion document:** [`user-block-design.md`](./user-block-design.md) holds the
*rationale* (why the cascade is sybil-scoped, why B3 is a publish gate and not negative
evidence, what the network-dynamics consequences are). This document holds the
*instructions*. When the two disagree, the design doc wins on "why" and this one wins on
"what to type".

**Audience:** a code-generating model (Composer-class) executing §12 subtasks one at a
time, reviewed by a stronger model. Every subtask is self-contained: exact files, exact
signatures, exact acceptance criteria.

---

## 0. Rules the implementer must not break

These are enforced by lints or CI. Violating one fails review regardless of whether the
feature works.

**Layering** (`.cursor/rules/architecture.mdc`) — dependency direction is
`UI → Data → Domain → nothing`:

- Domain never imports `data/` or `ui/`. Server check that must stay empty:
  `rg "package:tentura_server/data/repository" packages/server/lib/domain`
- Use cases import `domain/port/` only. Repositories register
  `@Injectable(as: …Port)` / `@Singleton(as: …Port)`.
- Data never imports UI. Ferry/Drift types never leave the data layer — repositories
  return domain entities.
- A cubit touching ≥2 repositories **must** go through a `*_case.dart` use case (lint
  `cubit_requires_use_case_for_multi_repos`). A thin single-repository cubit may inject
  the repository directly.
- Cubits never import `data/service/` (lint `no_cubit_to_data_service_import`).
- Use cases `@singleton`, repositories `@lazySingleton`.

**Codegen** (`.cursor/rules/codegen.mdc`):

- GraphQL lives in `.graphql` files, never inline in Dart (lint `no_raw_graphql_in_dart`).
- Never hand-edit `*.g.dart`, `*.gr.dart`, `*.freezed.dart`, `*.config.dart`.
- After DI or GraphQL changes: `dart run build_runner build -d` in the affected package.

**Design system** (`material-3-flutter` skill, `.cursor/rules/tentura-design-system.mdc`):

- No raw `EdgeInsets.*(<number>)`, `BorderRadius`/`Radius.*(<number>)`, inline
  `fontSize:`, `Color(0x…)`, or `TextStyle(…)` literals anywhere under `features/**` or
  `ui/**`. Use `context.tt` tokens, `TenturaText.*`, `Theme.of(context).colorScheme.*`.
- Reach for an existing `Tentura*` component before a themed Material widget, and a
  themed Material widget before a hand-rolled `Container`.
- If no token fits, **add one to the design system first** — never inline a constant.

**Schema ownership** (see `AGENTS.md`): Drift does **not** own the Postgres schema.
Adding a table means all three of:
1. a Drift `Table` class **and** registration in `tentura_db.dart`'s `@DriftDatabase(tables: […])`,
2. `dart run build_runner build -d`,
3. a raw-SQL migration in `packages/server/lib/data/database/migration/mNNNN.dart`,
   registered in `_migrations.dart` (both the `part` line and the `InMemory([...])` list).

**Migration numbering:** the highest existing migration is **`m0134`**. This feature uses
`m0135`, `m0136`, `m0137`. Do not renumber, do not reuse, do not edit an existing
migration.

**Terminology** (`.cursor/rules/terminology.mdc`): users see *Request* / *Chat*; code
paths stay `beacon_*`. "Block" has no such split — user-facing and code both say block.
Never introduce a `Request` domain type.

---

## 1. Vocabulary (fixed names — do not invent synonyms)

| Term | Meaning | Identifier |
|---|---|---|
| **blocker** | the user performing the block | `blocker_id` |
| **blocked** | the user hidden by a block row | `blocked_id` |
| **origin** | why this row exists: the directly blocked user it descends from | `origin_id` |
| **direct block** | `origin_id = blocked_id` — the user chose this person explicitly | — |
| **inherited block** | `origin_id <> blocked_id` — materialized by a cascade | — |
| **intent** | the user's declared action (one row per direct block) | `user_block_intent` |
| **effective set** | everything in `user_block`; direct + inherited | — |
| **cascade** | materializing invite-descendants of a directly blocked user | `cascade_mode` |
| **attached** | the candidate has independent standing ⇒ excluded from cascade | `block_cascade_unattached() = false` |
| **withdrawal (B3)** | zeroing the blocker's published MeritRank edge | not a column — implied by any `user_block` row |

`cascade_mode`: `0` none · `1` sybil-scoped (recommended default when cascade is on) ·
`2` all descendants.

**Withdrawal is unconditional.** Blocking someone *is* ceasing to vouch for them; there is
no separate opt-in, no `penalize` flag, and no code path where a block leaves a positive
published edge standing. The UI states it as a consequence, never as a choice (§8.3). This
is the one place the spec deliberately has fewer knobs than the design doc's early drafts —
do not add one back.

`cascade_status`: `0` pending · `1` running · `2` done · `3` capped.

---

## 2. Database schema — migration `m0135`

File: `packages/server/lib/data/database/migration/m0135.dart`, registered in
`_migrations.dart`. One SQL statement per list element (migrant uses prepared statements).

```dart
part of '_migrations.dart';

/// User blocking: effective block set, declared intent, and the cascade
/// membership predicate. See docs/plans/user-block-design.md §4, §6.
final m0135 = Migration('0135', [
  r'''
CREATE TABLE IF NOT EXISTS public.user_block (
  blocker_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  blocked_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  origin_id  text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_block_pkey PRIMARY KEY (blocker_id, blocked_id, origin_id),
  CONSTRAINT user_block__no_self CHECK (blocker_id <> blocked_id)
);
''',
  'CREATE INDEX IF NOT EXISTS user_block_reverse_idx ON public.user_block (blocked_id, blocker_id);',
  'CREATE INDEX IF NOT EXISTS user_block_origin_idx  ON public.user_block (blocker_id, origin_id);',
  r'''
CREATE TABLE IF NOT EXISTS public.user_block_intent (
  blocker_id         text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  blocked_id         text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  cascade_mode       smallint NOT NULL DEFAULT 0 CHECK (cascade_mode IN (0,1,2)),
  cascade_status     smallint NOT NULL DEFAULT 0 CHECK (cascade_status IN (0,1,2,3)),
  cascade_cursor     text,
  cascade_snapshot_at timestamptz,
  materialized_count integer NOT NULL DEFAULT 0,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_block_intent_pkey PRIMARY KEY (blocker_id, blocked_id),
  CONSTRAINT user_block_intent__no_self CHECK (blocker_id <> blocked_id)
);
''',
  'CREATE INDEX IF NOT EXISTS user_block_intent_pending_idx ON public.user_block_intent (cascade_status) WHERE cascade_status IN (0,1);',
  // §2.1 — the one predicate every read site calls
  r'''
CREATE OR REPLACE FUNCTION public.block_hides(_a text, _b text)
RETURNS boolean LANGUAGE sql STABLE PARALLEL SAFE AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_block WHERE blocker_id = _a AND blocked_id = _b)
      OR EXISTS (SELECT 1 FROM public.user_block WHERE blocker_id = _b AND blocked_id = _a);
$$;
''',
  // §2.2 — cascade membership
  r'''
CREATE OR REPLACE FUNCTION public.block_cascade_unattached(
  _blocker text, _root text, _candidate text
) RETURNS boolean LANGUAGE sql STABLE PARALLEL SAFE AS $$
  SELECT CASE WHEN _candidate = _blocker THEN false ELSE NOT (
    -- (a) the blocker mutually trusts the candidate themselves
    EXISTS (
      SELECT 1
      FROM public.vote_user m_out
      JOIN public.vote_user m_in
        ON m_in.subject = _candidate AND m_in.object = _blocker
      WHERE m_out.subject = _blocker AND m_out.object = _candidate
        AND m_out.amount > 0 AND m_in.amount > 0)
    -- (b) or someone the blocker mutually trusts vouches for the candidate
    OR EXISTS (
      SELECT 1
      FROM public.vote_user v_out
      JOIN public.vote_user v_in
        ON v_in.subject = v_out.object AND v_in.object = _candidate
      WHERE v_out.subject = _candidate
        AND v_out.amount > 0 AND v_in.amount > 0
        AND v_out.object <> _root
        AND v_out.object <> _blocker
        AND NOT EXISTS (
          SELECT 1 FROM public.user_block ub
          WHERE ub.blocker_id = _blocker AND ub.blocked_id = v_out.object)
        AND EXISTS (
          SELECT 1 FROM public.vote_user b_out
          JOIN public.vote_user b_in
            ON b_in.subject = b_out.object AND b_in.object = _blocker
          WHERE b_out.subject = _blocker AND b_out.object = v_out.object
            AND b_out.amount > 0 AND b_in.amount > 0))
  ) END;
$$;
''',
  // §2.3 — cascade candidate set, guarded descent
  r'''
CREATE OR REPLACE FUNCTION public.block_cascade_candidates(
  _blocker text, _root text, _mode smallint, _max_depth integer, _limit integer
) RETURNS TABLE (user_id text, depth integer)
  LANGUAGE sql STABLE AS $$
WITH RECURSIVE sub AS (
  SELECT g.descendant_node_key AS k, g.descendant_user_id AS uid, 1 AS depth
  FROM public.invite_genealogy g
  WHERE g.ancestor_user_id = _root
  UNION ALL
  SELECT g.descendant_node_key, g.descendant_user_id, s.depth + 1
  FROM public.invite_genealogy g
  JOIN sub s ON g.ancestor_node_key = s.k
  WHERE s.depth < _max_depth
    -- never descend through the blocker: everything below them is their own
    -- invite subtree, in either mode
    AND s.uid IS DISTINCT FROM _blocker
    -- descend through deleted (anonymized) nodes unconditionally; the tree
    -- structure survives account deletion even though uid becomes NULL
    AND (s.uid IS NULL
         OR _mode = 2
         OR public.block_cascade_unattached(_blocker, _root, s.uid))
)
SELECT s.uid, min(s.depth)::int
FROM sub s
WHERE s.uid IS NOT NULL
  AND s.uid <> _blocker
  AND (_mode = 2 OR public.block_cascade_unattached(_blocker, _root, s.uid))
GROUP BY s.uid
ORDER BY 2, 1
LIMIT _limit;
$$;
''',
]);
```

### 2.4 Why the descent is guarded (do not "simplify" this)

The recursive step stops descending through a node that is **attached**. Without the
guard, backfill and the signup trigger (§4) would disagree: a grandchild of an attached
node would be blocked by backfill but not by the trigger. The guard makes both obey the
same rule — *someone who entered through a person with independent standing is not
treated as a puppet*.

The `s.uid IS NULL` branch is load-bearing: `invite_genealogy` nulls `descendant_user_id`
when an account is deleted, but the node key and tree structure remain. Without that
branch the predicate returns `NULL`, the `WHERE` fails, and the descent silently stops at
every deleted account.

### 2.5 Blocking your own ancestor (do not weaken these two guards)

When A blocks R and A is herself a descendant of R, the candidate set contains A **and
everyone A invited**. Two guards handle it, and both are needed:

- `_candidate = _blocker → false` in `block_cascade_unattached` makes the blocker
  permanently *attached*. The guarded descent therefore stops at the blocker and never
  enters her subtree.
- `s.uid IS DISTINCT FROM _blocker` in the recursive step does the same thing
  structurally, as defense-in-depth: it stops the descent one step earlier, without
  relying on `block_cascade_unattached` being called at all. (An earlier draft had a
  second cascade mode that skipped the predicate entirely — see design §6.1 — which is
  why this guard exists independently of the predicate; it was removed in m0138, but the
  guard is still correct and cheap to keep.)

`s.uid <> _blocker` in the outer `SELECT` is the last line of defence: without it the
insert violates `user_block__no_self` and aborts the whole batch.

> An earlier draft tried to express this as
> `NOT EXISTS (… bg.ancestor_user_id = _blocker)`. That is **wrong** — `invite_genealogy`
> is a parent-pointer table, so it only matches the blocker's *direct* invitees and lets
> grandchildren through. Do not reintroduce it.

---

## 3. Enforcement SQL — migration `m0136`

### 3.1 Beacon permission wall (the main chokepoint)

Re-declare `beacon_can_read_content` with the block clause **first**. Copy the rest of the
body verbatim from `m0124` — do not restructure it.

```sql
CREATE OR REPLACE FUNCTION public.beacon_can_read_content(
  p_beacon_id text, p_viewer_id text
) RETURNS boolean LANGUAGE sql STABLE AS $$
SELECT COALESCE((
  SELECT CASE
    WHEN public.block_hides(b.user_id, p_viewer_id) THEN false   -- NEW
    WHEN b.status = 3 THEN b.user_id = p_viewer_id
    WHEN b.status = 2 THEN false
    WHEN b.user_id = p_viewer_id THEN true
    WHEN EXISTS (SELECT 1 FROM public.beacon_forward_edge fe
                 WHERE fe.beacon_id = p_beacon_id AND fe.recipient_id = p_viewer_id
                   AND fe.cancelled_at IS NULL) THEN true
    WHEN EXISTS (SELECT 1 FROM public.beacon_participant bp
                 WHERE bp.beacon_id = p_beacon_id AND bp.user_id = p_viewer_id
                   AND (bp.role = 1 OR bp.room_access = 3)) THEN true
    WHEN EXISTS (SELECT 1 FROM public.beacon_help_offer ho
                 WHERE ho.beacon_id = p_beacon_id AND ho.user_id = p_viewer_id
                   AND ho.status = 0) THEN true
    ELSE false
  END
  FROM public.beacon b WHERE b.id = p_beacon_id
), false);
$$;
```

`beacon_can_read_involvement` calls `beacon_can_read_content`, so it inherits the clause
with no edit. Do not touch it.

### 3.2 Graph functions

Wrap both graph readers. `graph()` keeps its `hasura_session` argument; use it for the
viewer id.

```sql
CREATE OR REPLACE FUNCTION public.graph(
  focus text, context text, positive_only boolean, hasura_session json
) RETURNS SETOF public.graph_score LANGUAGE sql STABLE AS $$
SELECT g.src, g.dst, g.score_cluster_of_ego, g.score_cluster_of_dst,
       public.user_trust_edge_degree(g.src, positive_only),
       public.user_trust_edge_degree(g.dst, positive_only)
FROM mr_graph(hasura_session ->> 'x-hasura-user-id', focus, context,
              positive_only, 0, 100) AS g
WHERE NOT public.block_hides(hasura_session ->> 'x-hasura-user-id', g.src)
  AND NOT public.block_hides(hasura_session ->> 'x-hasura-user-id', g.dst);
$$;
```

`graph_edges_between` has **no** session argument today. Add one (`hasura_session json`)
and update `hasura/metadata.json` to declare `"session_argument": "hasura_session"` for
it, mirroring the `graph` entry. Filter both endpoints with `block_hides`.

> This changes the function signature. Drop the old one first
> (`DROP FUNCTION IF EXISTS public.graph_edges_between(text[], boolean);`) in the same
> migration, and update the client `.graphql` operation to stop passing positional args
> that no longer match.

### 3.3 Mutual friends

`mutual_friends(alice, bob, ctx)` — **the live definition is in `m0078`, not `m0031`;
copy from `m0078`**: add
`AND NOT public.block_hides(alice, <result user id>)` to the final projection, and return
zero rows when `block_hides(alice, bob)`.

### 3.4 Presence

`hasura/metadata.json`, table `user_presence`, role `user`: add a computed field
`user_presence_hidden_for_viewer(hasura_session)` and the filter
`{"hidden_for_viewer": {"_eq": false}}`.

### 3.5 User search / profile

Add a computed field on `public."user"`:

```sql
CREATE OR REPLACE FUNCTION public.user_hidden_for_viewer(
  user_row public."user", hasura_session json
) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT public.block_hides(hasura_session ->> 'x-hasura-user-id', user_row.id);
$$;
```

Register it in `hasura/metadata.json` under the `user` table's `computed_fields`, add
`"hidden_for_viewer"` to the role's `computed_fields` list, and set the select permission
filter to `{"hidden_for_viewer": {"_eq": false}}`.

---

## 4. Signup inheritance trigger — part of `m0136`

```sql
CREATE OR REPLACE FUNCTION public.user_block_inherit_on_invite()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.descendant_user_id IS NULL OR NEW.ancestor_user_id IS NULL THEN
    RETURN NULL;
  END IF;
  INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
  SELECT ub.blocker_id, NEW.descendant_user_id, ub.origin_id
  FROM public.user_block ub
  WHERE ub.blocked_id = NEW.ancestor_user_id
    AND ub.blocker_id <> NEW.descendant_user_id
    AND EXISTS (
      SELECT 1 FROM public.user_block_intent i
      WHERE i.blocker_id = ub.blocker_id
        AND i.blocked_id = ub.origin_id
        AND i.cascade_mode > 0)
  ON CONFLICT DO NOTHING;
  RETURN NULL;
END; $$;

CREATE OR REPLACE TRIGGER user_block_inherit_trg
  AFTER INSERT ON public.invite_genealogy
  FOR EACH ROW EXECUTE FUNCTION public.user_block_inherit_on_invite();
```

**No mode branch and no standing predicate here, by design.** An `invite_genealogy` row is
only written at signup, so the descendant has no `vote_user` rows yet and
`block_cascade_unattached` is unconditionally true. Adding the predicate would be dead
weight that also introduces an ordering hazard.

`ub.blocker_id <> NEW.descendant_user_id` guards the `user_block__no_self` CHECK in the
pathological case where the new account's ancestor is blocked *by that same new account*
(impossible today, but the constraint violation would abort the signup transaction).

---

## 5. B3 withdrawal gate — migration `m0137`

Re-declare `trust_rebuild_effective_edge` from `m0122` with **one** change: the value
published to MeritRank is gated. Everything else — the pair lock, the source-context sum,
the `user_trust_edge` upsert with the honest projection — is copied verbatim.

```sql
  -- … unchanged through the user_trust_edge upsert …

  _target := CASE
    WHEN EXISTS (SELECT 1 FROM public.user_block
                 WHERE blocker_id = _subject AND blocked_id = _object)
    THEN 0 ELSE _w END;

  IF abs(_target - _prev) > _eps THEN
    BEGIN
      PERFORM mr_put_edge(_subject, _object, _target, ''::text, 0);
      UPDATE public.user_trust_edge SET prev_sent_weight = _target, updated_at = now()
      WHERE subject = _subject AND object = _object;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'trust_rebuild_effective_edge: publish %->% deferred: %',
        _subject, _object, SQLERRM;
    END;
  END IF;

  RETURN _w;   -- still the honest weight, not _target
```

Declare `_target double precision;` alongside `_w`.

**Invariants:**
- `user_trust_source_edge` and `trust_evidence_event` are never written by blocking.
- `user_trust_edge.s_*` keeps the honest projection.
- `prev_sent_weight` keeps its meaning: *what was last published*.
- `RETURN _w` stays honest so callers that use the return value are unaffected.

**Callers must pass `-1` as `_epsilon_override` on block and unblock.** The target changed
while `_w` did not, so the normal epsilon gate would suppress the republish.

**Direction:** only `subject = blocker` is gated. Never gate the reverse edge.

**Scope:** the `EXISTS` queries `user_block` and nothing else. Two consequences, both
intentional:
- it covers inherited (cascade) rows automatically — do **not** add
  `AND blocked_id = origin_id`;
- there is **no `penalize` check**, because withdrawal is unconditional (§1). The gate is
  literally "is this pair blocked", which is why this migration needs no knowledge of the
  intent table at all.

---

## 6. Server Dart layer

### 6.1 Drift tables

`packages/server/lib/data/database/table/user_blocks.dart`:

```dart
class UserBlocks extends Table {
  TextColumn get blockerId => text().named('blocker_id')();
  TextColumn get blockedId => text().named('blocked_id')();
  TextColumn get originId  => text().named('origin_id')();
  DateTimeColumn get createdAt => dateTime().named('created_at')();

  @override
  Set<Column<Object>> get primaryKey => {blockerId, blockedId, originId};
  @override
  String get tableName => 'user_block';
}
```

`user_block_intents.dart` analogous (`user_block_intent`, PK `{blockerId, blockedId}`).

Register both in `packages/server/lib/data/database/tentura_db.dart`'s
`@DriftDatabase(tables: […])` **and** import the entity file there, then run
`dart run build_runner build -d` in `packages/server`.

### 6.2 Domain entities

`packages/server/lib/domain/entity/user_block_entity.dart` (Freezed):

```dart
@freezed
abstract class UserBlockEntity with _$UserBlockEntity {
  const factory UserBlockEntity({
    required String blockerId,
    required String blockedId,
    required String originId,
    required DateTime createdAt,
  }) = _UserBlockEntity;
  const UserBlockEntity._();

  bool get isDirect => blockedId == originId;
}

@freezed
abstract class UserBlockIntentEntity with _$UserBlockIntentEntity {
  const factory UserBlockIntentEntity({
    required String blockerId,
    required String blockedId,
    @Default(0) int cascadeMode,
    @Default(0) int cascadeStatus,
    @Default(0) int materializedCount,
    required DateTime createdAt,
  }) = _UserBlockIntentEntity;
}

@freezed
abstract class BlockPreviewEntity with _$BlockPreviewEntity {
  const factory BlockPreviewEntity({
    @Default(0) int cascadeCandidateCount,
    @Default(false) bool cascadeCapped,
    @Default(0) int openCommitmentCount,
    @Default(false) bool willWithdrawEdge,
  }) = _BlockPreviewEntity;
}
```

### 6.3 Port

`packages/server/lib/domain/port/user_block_repository_port.dart`:

```dart
abstract class UserBlockRepositoryPort {
  Future<void> block({
    required String blockerId,
    required String blockedId,
    required int cascadeMode,
  });

  Future<void> unblock({required String blockerId, required String blockedId});

  /// Promote an inherited row to a direct block (§6.3 escape hatch).
  Future<void> promoteToDirect({required String blockerId, required String blockedId});

  Future<List<UserBlockIntentEntity>> listIntents(String blockerId);

  Future<List<UserBlockEntity>> listInherited({
    required String blockerId,
    required String originId,
  });

  Future<BlockPreviewEntity> preview({
    required String blockerId,
    required String blockedId,
    required int cascadeMode,
  });

  Future<bool> isBlockedPair({required String a, required String b});

  /// Batch form for list surfaces — one round trip.
  Future<Set<String>> hiddenPeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  });

  // --- cascade job surface ---
  Future<List<UserBlockIntentEntity>> claimPendingCascades({required int limit});
  Future<int> materializeCascadeBatch({
    required String blockerId,
    required String blockedId,
    required int limit,
  });
  Future<int> runReleaseSweep({required int limit});
}
```

### 6.4 Repository

`packages/server/lib/data/repository/user_block_repository.dart`,
`@Injectable(as: UserBlockRepositoryPort, env: [Environment.dev, Environment.prod])`.

**Scope discipline:** this repository owns `user_block` and `user_block_intent` **only**.
It must not write `beacon_help_offer`, `beacon_forward_edge`, or `user_contact` — those
belong to their own repositories, and cross-repository orchestration is the use case's job
(§6.5). A repository calling another repository is a layering violation.

`block()` writes, in one transaction:
1. `INSERT … user_block_intent … ON CONFLICT (blocker_id, blocked_id) DO UPDATE SET cascade_mode = …, cascade_status = 0, cascade_snapshot_at = now(), updated_at = now()`
2. `INSERT INTO user_block (blocker_id, blocked_id, origin_id) VALUES ($1,$2,$2) ON CONFLICT DO NOTHING`

`applyWithdrawal({blockerId, blockedId})` — separate method, called by the use case on
**every** block: run `SELECT trust_rebuild_effective_edge($1, $2, -1)` **only if** a
`user_trust_edge` row with `prev_sent_weight <> 0` exists for the pair. The `only if` is a
cost optimization, not a semantic choice — with no edge there is nothing to withdraw.

`unblock()` runs one transaction:
1. capture the affected pairs *before* deleting:
   `SELECT blocked_id FROM user_block WHERE blocker_id = $1 AND origin_id = $2`
2. `DELETE FROM user_block WHERE blocker_id = $1 AND origin_id = $2`
3. `DELETE FROM user_block_intent WHERE blocker_id = $1 AND blocked_id = $2`
4. for each captured pair that has a `user_trust_edge` row:
   `SELECT trust_rebuild_effective_edge($1, pair, -1)`

Step 1 before step 2 is mandatory — after the delete the set is unrecoverable.

`promoteToDirect()` inserts `(blocker, blocked, blocked)` and an intent row with
`cascade_mode = 0`, leaving any inherited rows in place.

### 6.5 Use case

`packages/server/lib/domain/use_case/user_block_case.dart`, `@Singleton(order: 2)`,
extends `UseCaseBase`. This is the **only** place that spans repositories, so it owns the
transaction. Inject `UserBlockRepositoryPort`, `MutatingUnitOfWorkPort`,
`HelpOfferRepositoryPort`, `UserContactRepositoryPort`, `UserRepositoryPort`
(plus `env`, `logger`).

Follow the shape of `UserTrustEdgeCase.setUserVote`: wrap the whole action in the unit of
work so the block row, the cleanup, and the withdrawal commit or roll back together.

```dart
Future<void> block({
  required String blockerId,
  required String blockedId,
  required int cascadeMode,
}) {
  if (blockerId == blockedId) {
    throw ArgumentError.value(blockedId, 'blockedId', 'cannot block yourself');
  }
  return _unitOfWork.run(
    actorUserId: blockerId,
    action: () async {
      await _users.getById(blockedId);            // throws IdNotFoundException
      await _enforceRateLimit(blockerId);
      await _blocks.block(
        blockerId: blockerId,
        blockedId: blockedId,
        cascadeMode: cascadeMode,
      );
      await _cleanupDirectPair(blockerId, blockedId);
      await _blocks.applyWithdrawal(blockerId: blockerId, blockedId: blockedId);
    },
  );
}
```

Rate limit: `Env.blockRateLimitPerDay` (default 50), throwing the rate-limit exception
type introduced by the security-hardening pass — do not invent a new one.

### 6.6 One-shot cleanup — `_cleanupDirectPair`

Applies to **direct** blocks only. Cascade-derived rows never trigger cleanup, because the
user was never shown a warning for people they did not individually choose.

Go through the owning repositories, not raw SQL, so their bookkeeping
(`withMutatingUser`, `withdrawReason`, attention side effects) stays intact:

| What | How |
|---|---|
| pending help offers, both directions | `HelpOfferRepositoryPort.withdraw(beaconId:, userId:, withdrawReason: kBlockWithdrawReason)` for each offer with `status == 0` between the pair. **Withdrawn is `status == 1`**, set by that method — never write the status yourself. |
| uncancelled forward edges, both directions | the existing forward-edge cancel path (`cancelled_at` is an already-modelled state) |
| contact rows, both directions | `UserContactRepositoryPort` delete |

Define `kBlockWithdrawReason` as a const in the block feature's domain layer.

Room participation is **not** cleaned up here — see §7.4.

### 6.7 Cascade job

`packages/server/lib/domain/use_case/block_cascade_case.dart`, wired into
`TaskWorkerCase` next to `AttentionExpirySweepCase`. Two responsibilities, same
`runDue()` shape as `TrustMaintenanceCase` (interval, retry, time budget from `Env`):

**Materialization.** For each intent with `cascade_status IN (0,1)`:
1. set `cascade_status = 1`, `cascade_snapshot_at = COALESCE(cascade_snapshot_at, now())`;
2. call `block_cascade_candidates(blocker, blocked, mode, Env.blockCascadeMaxDepth,
   Env.blockCascadeMaxRows + 1)` **once**, snapshot the ids;
3. insert in batches of `Env.blockCascadeBatchSize`, `ON CONFLICT DO NOTHING`,
   `origin_id = blocked_id`;
4. if the candidate query returned more than `blockCascadeMaxRows`, truncate and set
   `cascade_status = 3` (capped); else `2` (done);
5. **catch-up pass:** re-run for `invite_genealogy.created_at > cascade_snapshot_at` to
   close the race where an account signed up after the snapshot but before its ancestor
   was inserted (§11.7);
6. for each newly inserted row whose pair has a `user_trust_edge` row:
   `trust_rebuild_effective_edge(blocker, blocked, -1)` — withdrawal follows the effective
   set unconditionally;
7. re-read the intent row before each batch; if it is gone (unblocked mid-run), abort
   and delete nothing — `unblock()` already removed the rows.

**Release sweep** (mode 1 only):

Bounded by `_limit` — the predicate is not free, and an unbounded `DELETE` would hold row
locks across the whole inherited set:

```sql
WITH candidates AS (
  SELECT ub.blocker_id, ub.blocked_id, ub.origin_id
  FROM public.user_block ub
  JOIN public.user_block_intent i
    ON i.blocker_id = ub.blocker_id AND i.blocked_id = ub.origin_id
  WHERE i.cascade_mode = 1
    AND ub.blocked_id <> ub.origin_id
    AND (ub.blocker_id, ub.blocked_id, ub.origin_id) > ($1, $2, $3)  -- cursor
  ORDER BY ub.blocker_id, ub.blocked_id, ub.origin_id
  LIMIT $4
),
releasable AS (
  SELECT * FROM candidates c
  WHERE NOT public.block_cascade_unattached(c.blocker_id, c.origin_id, c.blocked_id)
)
DELETE FROM public.user_block ub
USING releasable r
WHERE ub.blocker_id = r.blocker_id
  AND ub.blocked_id = r.blocked_id
  AND ub.origin_id  = r.origin_id
RETURNING ub.blocker_id, ub.blocked_id;
```

The driver advances the cursor over **candidates**, not over deletions — otherwise rows
that were examined and kept would be re-examined forever and the sweep would never reach
the tail. Persist the cursor per pass and reset it to `('','','')` when a pass completes.

For each returned pair with a `user_trust_edge` row, call
`trust_rebuild_effective_edge(blocker, blocked, -1)` to restore the honest weight.

New `Env` knobs (add to `packages/server/lib/env.dart`, document defaults in
`.env.example`): `BLOCK_RATE_LIMIT_PER_DAY=50`, `BLOCK_CASCADE_MAX_DEPTH=6`,
`BLOCK_CASCADE_MAX_ROWS=5000`, `BLOCK_CASCADE_BATCH_SIZE=500`,
`BLOCK_RELEASE_SWEEP_INTERVAL=6h`.

### 6.8 V2 GraphQL API

`packages/server/lib/api/controllers/graphql/mutation/mutation_user_block.dart`, registered
in `_mutations_all.dart`:

| Field | Args | Returns |
|---|---|---|
| `userBlock` | `objectId: String!`, `cascadeMode: Int` | `Boolean!` |
| `userUnblock` | `objectId: String!` | `Boolean!` |
| `userBlockPromote` | `objectId: String!` | `Boolean!` |

`.../query/query_user_block.dart`, registered in `_queries_all.dart`:

| Field | Args | Returns |
|---|---|---|
| `myBlocks` | — | `[BlockIntent!]!` (blocked profile + counts + mode) |
| `blockInherited` | `originId: String!` | `[UserPublic!]!` |
| `blockPreview` | `objectId: String!`, `cascadeMode: Int` | `BlockPreview!` |

All resolvers take the blocker from `getCredentials(args).sub` — **never** from an
argument. Follow the shape of `mutation_contact.dart`.

---

## 7. Enforcement matrix — exact call sites

| # | Surface | File | Change |
|---|---|---|---|
| E1 | Beacon feed / fetch / room access | `m0136` | `beacon_can_read_content` clause (§3.1) |
| E2 | Forward | `domain/use_case/forward_case.dart` | in `forward()`, drop blocked recipients from `recipientIds` before the guard loop; the result map is already per-recipient |
| E3 | Forward suggestions | `beacon_lineage_suggestions_case.dart`, `query_forward_graph.dart`, `query_forward_inbound.dart` | filter candidates via `hiddenPeerIds` |
| E4 | Help offer | `help_offer_case.dart` | reject when `isBlockedPair(offerer, beaconAuthor)` |
| E5 | Room message send + admission | `beacon_room_case.dart`, `coordination_case.dart` | reject when the pair is blocked |
| E6 | Contact set | `contact_case.dart` | reject |
| E7 | Invitation accept | `invitation_case.dart`, `root_router.dart` accept endpoints | reject with 404 |
| E8 | Attention recipients | `attention_intent_case.dart` | filter in recipient assembly **before** the snapshot is recorded — the payload is immutable afterwards |
| E9 | Graph | `m0136` | `graph`, `graph_edges_between` (§3.2) |
| E10 | Mutual friends | `m0136` | `mutual_friends` (§3.3) |
| E11 | User search / profile | `hasura/metadata.json` | computed field (§3.5) |
| E12 | Presence | `hasura/metadata.json` | computed field (§3.4) |
| E13 | Invite genealogy | `invite_genealogy_repository.dart` | **anonymize, do not remove** — §7.3 |
| E14 | Coordination item assignment | `coordination_item_case.dart` | reject |

### 7.3 Genealogy rendering

Never drop a blocked node from the genealogy graph — that disconnects its subtree. Instead
reuse the existing deleted-account placeholder path: in
`InviteGenealogyRepository._buildNodes`, treat a blocked user id exactly as a null
`user_id` (placeholder node, structure preserved). One `hiddenPeerIds` call per fetch,
applied to the assembled node list. The result is indistinguishable from a deleted account
— which is the intended ambiguity.

### 7.4 Rooms with open commitments

Per design D2 the block ejects, but the user is warned first:

- **Direct block:** `blockPreview.openCommitmentCount` is surfaced in the sheet as a
  warning. Proceeding ejects (E1 does this automatically via `can_read_content`).
- **Inherited (cascade) block:** never ejects a room with an open commitment. The user
  was never shown a warning for people they did not individually choose, so the async
  process must not break their obligations. Implement by adding to
  `beacon_can_read_content` an exception for pairs whose only block row is inherited *and*
  which have an open `beacon_commitment`. If this proves awkward in SQL, ship v1 without
  the cascade eject at all (cascade hides discovery surfaces only) and note it.

### 7.5 Error shape

Guards may return an **honest** error ("blocked by this user"). Do not disguise as
not-found, do not equalize timing. §3 of the design doc accepts detectability; disguising
would mean auditing every path for error-shape and timing tells, forever.

---

## 8. Client implementation

New feature directory: `packages/client/lib/features/block/{domain,data,ui}`.

### 8.1 Domain

`domain/entity/user_block.dart` (Freezed):

```dart
@freezed
abstract class BlockIntent with _$BlockIntent {
  const factory BlockIntent({
    required Profile blocked,
    @Default(0) int cascadeMode,
    @Default(0) int inheritedCount,
    @Default(false) bool cascadeCapped,
    @Default(true) bool cascadePending,
  }) = _BlockIntent;
}

@freezed
abstract class BlockPreview with _$BlockPreview { /* mirrors §6.2 */ }
```

`domain/use_case/block_case.dart`, `@singleton` — injects `BlockRepository` plus the
cache-invalidation port (§8.5). This is a multi-collaborator workflow, so the cubit
**must** go through it, not the repository (lint `cubit_requires_use_case_for_multi_repos`).

### 8.2 Data

`data/gql/` — one `.graphql` file per operation, never inline:
`block_user.graphql` (`UserBlock`), `unblock_user.graphql` (`UserUnblock`),
`block_promote.graphql` (`UserBlockPromote`), `my_blocks_fetch.graphql` (`MyBlocks`),
`block_inherited_fetch.graphql` (`BlockInherited`),
`block_preview_fetch.graphql` (`BlockPreview`).

Register every operation name in `_tenturaDirectOperationNames` in
`packages/client/lib/data/service/remote_api_client/build_client.dart` — these resolve on
V2, not Hasura. Then `dart run build_runner build -d` in `packages/client`.

`data/repository/block_repository.dart`, `@lazySingleton`, returns domain entities only.

### 8.3 UI — block sheet

`ui/sheet/block_user_sheet.dart`. Use `showTenturaAdaptiveSheet` — it already renders a
bottom sheet on `WindowClass.compact` and a centered `maxWidth`-constrained dialog on
regular/expanded. **Do not hand-roll a `LayoutBuilder` here**; the responsive behavior is
the design system's job and duplicating it will drift.

Content, top to bottom:

1. Title `Text(l10n.blockUserTitle(profile.shownName))`, `textTheme.titleMedium`.
2. Body `l10n.blockUserExplainer`, `textTheme.bodyMedium` — states that they will no
   longer see each other and cannot contact each other.
3. `SwitchListTile` — "Also hide people they invited" (on → `cascadeMode: 1`, off →
   `cascadeMode: 0`). Default **off**. Subtitle names the effect in plain language
   (standing-aware, probationary), not a mode number. No nested choice: there is only
   one cascade mode (design §6.1); an earlier draft's "everyone in their invite branch,
   regardless of standing" mode was removed before shipping to users.
4. **Withdrawal notice — information, not a control.** When
   `preview.willWithdrawEdge` is true, render a non-interactive row: an
   `Icons.info_outline` icon plus `l10n.blockWithdrawNotice`, stating that blocking also
   stops vouching for this person in the trust graph and that unblocking restores it.
   Use `colorScheme.onSurfaceVariant`, `textTheme.bodySmall`.

   **It must not be a `SwitchListTile`, `Checkbox`, or anything tappable.** Withdrawal is
   unconditional (§1); presenting it as optional would be a lie about what the button
   does. Omit the row entirely when `willWithdrawEdge` is false — with no edge to
   withdraw, the statement would be false.
5. Impact block, populated from `blockPreview`: `l10n.blockPreviewCascade(n)` and, when
   `openCommitmentCount > 0`, a warning row using `colorScheme.error` /
   `tt.danger` with `Icons.warning_amber_outlined`.
6. Actions row: `TextButton` cancel + `FilledButton` confirm styled with
   `ButtonStyle(backgroundColor: WidgetStatePropertyAll(colorScheme.error), foregroundColor: WidgetStatePropertyAll(colorScheme.onError))`.

Spacing from `context.tt` (`screenHPadding`, `rowGap`, `sectionGap`) only. The preview
fetch is debounced and re-issued when (3) changes — the candidate count depends on
whether the cascade is on. Item (4) does not re-fetch: whether an edge exists is
independent of the cascade.

**The sheet therefore contains exactly one checkbox** — the cascade switch in (3).
Everything else is text, a warning, or the action row.

### 8.4 UI — blocked list screen

`ui/screen/blocked_users_screen.dart`, `@RoutePage()`, reachable from
`features/settings/ui/screen/settings_screen.dart`.

- `TenturaTopBar.of(context, …)` for the app bar.
- Body: `ListView.builder` (lazy — never a `Column` of all entries) wrapped in
  `Center` + `ConstrainedBox(maxWidth: tt.contentMaxWidth)` so it does not stretch on
  expanded windows.
- Row per direct block: `ListTile` with `TenturaAvatar`, `shownName`,
  subtitle `l10n.blockedHiddenViaInvites(n)` when `inheritedCount > 0`, trailing
  `TenturaTextAction` "Unblock".
- Tapping a row with `inheritedCount > 0` expands an inherited list fetched via
  `BlockInherited`. Each inherited row offers **Unhide** (removes that one row) and
  **Block directly** (promote — permanent until manually lifted, §6.3 escape hatch).
- Empty state: centered `Text` with `textTheme.bodyMedium`,
  `colorScheme.onSurfaceVariant`.
- While `cascadePending`, show a `LinearProgressIndicator` and the text
  "still hiding people…" — materialization is async and the count grows.

### 8.5 Cache invalidation

Blocking invalidates feed, graph, profile, search, genealogy and inbox caches at once.
Reuse the mechanism described in
`docs/plans/beacon-cross-screen-invalidation-refactor.md`; do **not** add per-screen
`fetch()` calls. Most "the block didn't work" reports are stale Ferry cache, not backend.

### 8.6 Entry point and blocked-profile rendering

- `features/profile_view/ui/widget/profile_view_app_bar.dart`: add a `PopupMenuItem`
  between the friend-removal item and the complaint item — "Block" when not blocked,
  "Unblock" when blocked.
- If the viewer opens a blocked person's profile by direct link, render a stripped profile
  (avatar, name, nothing else) plus an "Unblock" action rather than an error. The viewer
  owns the block; hiding it from them is pointless friction.

### 8.7 l10n

Add keys to **both** `packages/client/l10n/app_en.arb` and `app_ru.arb`, then regenerate.
No hardcoded user-facing strings anywhere.

Keys: `blockUserMenuItem`, `unblockUserMenuItem`, `blockUserTitle`,
`blockUserExplainer`, `blockCascadeToggle`, `blockCascadeToggleSubtitle`,
`blockCascadeModeSybil`, `blockCascadeModeSybilSubtitle`, `blockCascadeModeAll`,
`blockCascadeModeAllSubtitle`, `blockWithdrawNotice`,
`blockPreviewCascade`, `blockPreviewOpenCommitments`, `blockConfirmButton`,
`blockedUsersTitle`, `blockedUsersEmpty`, `blockedHiddenViaInvites`,
`blockedInheritedPending`, `blockUnhideOne`, `blockPromoteToDirect`,
`blockErrorRateLimited`, `errorBlockedByUser`.

---

## 9. Behavioral test suite — cascade ("tree") blocks

Server tests are pg-tagged integration tests: `@Tags(['pg'])` + `library;` at the top,
skip when Postgres is unreachable. Pattern to copy exactly:
`packages/server/test/data/repository/merit_score_lookup_test.dart`.
Run with `cd packages/server && dart test -x pg` for unit-only,
`dart test -t pg` for the integration set.

### 9.1 Canonical fixture

Every test in §9.2–§9.7 builds this and nothing else. Ids are fixed so failures are
readable.

```
invite_genealogy (arrows = inviter → invitee):

  Ublkroot0001 (R)
   ├── Ublkalice001 (A)   ← the blocker in all tests
   ├── Ublkbob00001 (B)   ← the block target
   │    ├── Ublkcarol001 (C)  — vouched by V
   │    │    └── Ublkdave0001 (D)  — no standing of its own
   │    ├── Ublkpupp0001 (P1) — no standing
   │    ├── Ublkpupp0002 (P2) — no standing
   │    │    └── Ublkpupp0003 (P3) — no standing
   │    └── Ublkerin0001 (E)  — mutually trusted by A directly
   └── Ublkvera0001 (V)   ← A's mutually trusted peer, outside B's subtree

vote_user mutual positive pairs:
  A↔V, A↔E, C↔V, P1↔P2

user_trust_edge (published):
  A→B  prev_sent_weight = +0.60
  A→P1 prev_sent_weight = +0.20   ← exists only so T-G5 can prove the gate reaches
                                     cascade members; A never interacted with P1
  B→A  prev_sent_weight = +0.50
  (no A→C, A→D, A→P2, A→P3, A→E edges)
```

**`vote_user` and `user_trust_edge` are separate tables and the fixture sets them
independently.** In production a `userVote` writes both, but the cascade predicate
(`block_cascade_unattached`) reads **only `vote_user`**, and the withdrawal gate reads
**only `user_block` + `user_trust_edge`**. Seed them directly, and do not assume that
adding a trust edge grants standing — it does not.

### 9.2 Group T-A — direct block

| # | Given | When | Then |
|---|---|---|---|
| T-A1 | fixture | A blocks B, mode 0 | `user_block` has exactly one row `(A,B,B)`; `user_block_intent` has `(A,B)` with `cascade_mode=0` |
| T-A2 | T-A1 | — | `block_hides(A,B)` **and** `block_hides(B,A)` are both true |
| T-A3 | T-A1 | — | `beacon_can_read_content(<B's beacon>, A)` = false **and** `beacon_can_read_content(<A's beacon>, B)` = false |
| T-A4 | T-A1 | A unblocks B | both tables empty for the pair; `block_hides` false both ways; beacons readable again |
| T-A5 | fixture | A blocks A | rejected — `ArgumentError` at the use case, and the CHECK would reject at SQL level |
| T-A6 | T-A1 | A blocks B again | idempotent: still exactly one `user_block` row; intent updated, not duplicated |
| T-A7 | T-A1 | B's account is deleted | all rows for the pair are gone via `ON DELETE CASCADE` |
| T-A8 | fixture | B blocks A, then A blocks B | two independent direct rows; `block_hides` true; unblocking one leaves the other |

### 9.3 Group T-B — cascade materialization, mode 1

**Expected effective set: `{B, P1, P2, P3}`.** Not C, not D, not E.

| # | Assertion |
|---|---|
| T-B1 | after materialization, `SELECT blocked_id FROM user_block WHERE blocker_id=A` = exactly `{B, P1, P2, P3}` |
| T-B2 | the `B` row has `origin_id = B` (direct); `P1/P2/P3` rows have `origin_id = B` (inherited); `isDirect` is true only for `B` |
| T-B3 | **E is excluded via clause (a)** — A mutually trusts E directly. `block_cascade_unattached(A,B,E)` = false |
| T-B4 | **C is excluded via clause (b)** — V vouches for C and A↔V is mutual. `block_cascade_unattached(A,B,C)` = false |
| T-B5 | **D is excluded by the guarded descent** even though `block_cascade_unattached(A,B,D)` = true on its own — the descent stops at C. *This is the test that catches an unguarded CTE.* |
| T-B6 | P3 is included — descent continues through the unattached P2 |
| T-B7 | **puppets cannot vouch each other out**: P1↔P2 is mutual, but neither is mutually trusted by A, so both stay unattached |
| T-B8 | `user_block_intent.cascade_status` ends at `2` (done); `materialized_count` = 3 |
| T-B9 | the candidate query is order-independent: running materialization in two batches yields the same set as one batch |

### 9.4 Group T-C — cascade_mode 2 removal (m0138)

Cascade mode 2 ("all descendants, standing ignored, never released") was removed from
the design before shipping to users — see design §6.1. Only `cascade_mode 0` (none) and
`1` (standing-aware, probationary) remain.

| # | Assertion |
|---|---|
| T-C1 | `cascade_mode = 2` is rejected by the `user_block_intent_cascade_mode_check` CHECK constraint |
| T-C2 | `block_cascade_candidates` always applies the standing filter (`block_cascade_unattached`) — there is no mode value that bypasses it |

### 9.5 Group T-D — inheritance at signup

| # | Given | When | Then |
|---|---|---|---|
| T-D1 | A blocked B mode 1, materialized | P4 signs up invited by **P2** (blocked) | `(A,P4,B)` exists — inherited automatically |
| T-D2 | same | X signs up invited by **C** (attached, not blocked) | no row for X — the frontier gates itself |
| T-D3 | same | Y signs up invited by **B** | `(A,Y,B)` exists |
| T-D4 | A blocked B **mode 0** | Z signs up invited by B | no row for Z |
| T-D5 | A and V both block B with cascade | W signs up invited by B | two rows: `(A,W,B)` and `(V,W,B)` |
| T-D6 | A blocked B mode 1 | a signup row is inserted with `descendant_user_id IS NULL` | trigger returns without error, inserts nothing |

### 9.6 Group T-E — overlapping cascades and origin semantics

| # | Given | When | Then |
|---|---|---|---|
| T-E1 | A blocked B mode 1 | A also blocks P2 directly | P2 has **two** rows: `(A,P2,B)` and `(A,P2,P2)` |
| T-E2 | T-E1 | A unblocks B | rows with `origin_id=B` are deleted; `(A,P2,P2)` survives; `block_hides(A,P2)` still true |
| T-E3 | T-E1 | A unblocks P2 | `(A,P2,P2)` deleted; `(A,P2,B)` survives; P2 still hidden |
| T-E4 | X is a descendant of both B and another blocked root B2 | A unblocks B | X still hidden via the B2 origin |
| T-E5 | T-E1 | — | unblocking B does **not** delete the `user_block_intent` row for P2 |

### 9.7 Group T-F — release sweep (probation)

| # | Given | When | Then |
|---|---|---|---|
| T-F1 | P1 is inherited-blocked | P1↔V becomes mutual (V is A-trusted) | sweep deletes `(A,P1,B)`; P1 visible again |
| T-F2 | B is directly blocked | B somehow becomes A-trusted | sweep **never** deletes the root row (`blocked_id <> origin_id` guard) |
| T-F3 | P2 promoted to direct | P2 earns standing | the direct row survives; only the inherited row (if any) goes |
| T-F5 | A→P1 edge was gated to 0 | P1 released | `trust_rebuild_effective_edge` republishes `+0.20`; `prev_sent_weight` = 0.20 |
| T-F6 | P1 released | P5 signs up invited by P1 | **no** inherited row — the frontier moved |
| T-F7 | P1↔P2 mutual only | sweep runs | neither released |

### 9.8 Group T-G — B3 withdrawal gate

| # | Given | When | Then |
|---|---|---|---|
| T-G1 | A→B is `+0.60` | A blocks B | `mr_put_edge(A,B,0)` called; `user_trust_edge.prev_sent_weight` = 0; **`user_trust_source_edge` rows byte-identical**; `user_trust_edge.s_*` unchanged |
| T-G2 | T-G1 | A unblocks B | `prev_sent_weight` back to `+0.60` exactly |
| T-G3 | A has no edge to E | A blocks E | no `mr_put_edge` call at all — no-op |
| T-G4 | T-G1 | — | `B→A` edge is untouched at `+0.50` |
| T-G5 | A→P1 is `+0.20`, cascade mode 1 | materialization runs | P1's edge is gated to 0 too — the gate keys off the effective set |
| T-G6 | T-G1 with `|w − prev| < epsilon` | block | the publish still happens — the `-1` epsilon bypass is mandatory |
| T-G7 | T-G1 | — | `trust_evidence_event` gained **zero** rows |
| T-G8 | A blocks B, then B is unblocked and re-blocked twice | `prev_sent_weight` ends at 0 and returns to `+0.60` on the final unblock — no drift, no accumulated error |

### 9.9 Group T-H — enforcement surfaces

One test per row of §7's matrix, each asserting both directions of the pair. Minimum set:
feed invisibility (E1), forward silently drops the recipient (E2), help offer rejected
(E4), room message rejected (E5), contact set rejected (E6), invite accept 404 (E7),
attention recipient excluded from the snapshot (E8), `graph()` omits both nodes (E9),
`mutual_friends` returns empty (E10), user search omits (E11), **genealogy returns a
placeholder node and the subtree stays connected** (E13).

E13 deserves an explicit structural assertion: fetch the genealogy with B blocked and
assert that D is still reachable from R in the returned edge list.

---

## 10. Client test suite

| # | Test | File |
|---|---|---|
| C1 | `BlockCase.block` calls the repository with the right cascade mode and triggers invalidation | `test/features/block/block_case_test.dart` |
| C2 | `BlockedUsersCubit` emits loading → success; error path emits the error effect | `.../blocked_users_cubit_test.dart` |
| C3 | Block sheet: cascade switch off by default; turning it on reveals the mode radios and re-fetches the preview | `.../block_user_sheet_test.dart` (widget) |
| C4 | Block sheet: the withdrawal notice renders when `willWithdrawEdge` is true and is absent otherwise — and is never a tappable control | same |
| C5 | Block sheet: open-commitment warning renders when `openCommitmentCount > 0` | same |
| C6 | Blocked list renders as a bottom-anchored list at 400px width and a centered constrained column at 1200px | `.../blocked_users_screen_responsive_test.dart` — pump at both sizes via `tester.view.physicalSize` |
| C7 | Golden for the blocked-user tile (light + dark) | `.../blocked_user_tile_golden_test.dart`, pattern from `test/features/inbox/inbox_item_tile_golden_test.dart` |
| C8 | No hardcoded strings: every visible string resolves through `L10n` | covered by review, not a test |

Client tests need `flutter test --dart-define=ENV=test`.

---

## 11. Adversarial corner cases

Each row is a test. They are separated from §9 because they encode *attacks and
pathologies*, not normal behavior.

| # | Scenario | Required behavior |
|---|---|---|
| X1 | **Invite laundering.** B is blocked with cascade; B asks unblocked friend F to send the invite instead | New account is **not** inherited. Accepted limitation — the cascade tracks the tree, not intent. F now owns the consequence (design §10.6 upward moderation signal). Assert no row, and document. |
| X2 | **Self-vote farming.** P1 votes for itself to fake standing | No effect: clause (a) needs blocker↔candidate, clause (b) excludes `v_out.object = _candidate`. Assert P1 stays blocked. |
| X3 | **Blocking your own ancestor.** A blocks R, who is A's own inviter | No row for A itself (`s.uid <> _blocker`), and **A's own invite subtree is excluded** (`NOT EXISTS` on `bg.ancestor_user_id = _blocker`). Without this the batch aborts on the `no_self` CHECK. |
| X4 | **Deleted account mid-tree.** C's account is deleted (`descendant_user_id → NULL`) but the node remains | Descent continues through the NULL node to D; D is evaluated on its own merits. Without the `s.uid IS NULL` branch the predicate returns NULL and the descent silently stops. |
| X5 | **Signup during materialization.** P4 signs up under P2 after the candidate snapshot but before P2's row is inserted | The catch-up pass (§6.7 step 5) closes the gap. Assert P4 ends up blocked. |
| X6 | **Unblock during materialization.** A unblocks B while the job is mid-batch | Job aborts on the next intent re-read and inserts nothing further; no orphan rows remain. |
| X7 | **Mutual concurrent block.** A blocks B while B blocks A | No deadlock: `trust_pair_lock` hashes `subject‖0x1F‖object`, so A→B and B→A are different locks. Assert both complete. |
| X8 | **Cascade DoS.** A blocks a hub with 200 000 descendants | Capped at `BLOCK_CASCADE_MAX_ROWS`, `cascade_status = 3`, request latency unaffected (job is async), rate limit prevents repetition. |
| X9 | **Block/unblock churn.** 1 000 block→unblock cycles | `user_block` and `user_block_intent` return to zero rows; `user_trust_source_edge` unchanged; `prev_sent_weight` returns to its original value. |
| X10 | **Voucher later blocked.** V vouched for C; A then blocks V | On the next sweep, C loses its only voucher and — if still inside a live cascade — becomes eligible again. Assert the predicate re-evaluates rather than caching. |
| X11 | **Cross-root voucher.** X is vouched only by B2, and A has blocked both B and B2 | X is unattached under both cascades: the `v_out.object <> _root` clause passes for the other root, but the `NOT EXISTS user_block` clause discards a blocked voucher. Assert X blocked. |
| X12 | **Origin user deleted.** The cascade root B is deleted | All rows with `origin_id = B` vanish via `ON DELETE CASCADE`, including the direct row. Assert the descendants become visible again — the thing they were derived from no longer exists. |
| X13 | **Open commitment eject.** A blocks B while a `beacon_commitment` between them is open | Direct block: preview reports `openCommitmentCount = 1`, and proceeding ejects. Inherited block: **never** ejects (§7.4). |
| X14 | **Rate limit.** A issues 51 blocks in a day with the default knob | The 51st is rejected with the rate-limit error; the first 50 persist. |
| X15 | **Blocked user re-registers** with a fresh account not invited by anyone blocked | Not caught. Accepted and documented — the block is identity-scoped, not person-scoped. |
| X16 | **Steward blindness.** A is steward of a beacon whose author B they blocked | The beacon disappears from A's view. Accepted; note in the release notes so it is not reported as data loss. |

---

## 12. TODO — implementation subtasks

Execute in order. Each subtask is one commit. **Do not start a subtask whose dependencies
are unmerged.** Each ends with its own acceptance check; if the check fails, fix within
that subtask rather than deferring.

### Phase 1 — schema (server)

**S1 · Migration `m0135`: tables + predicates**
Files: `migration/m0135.dart`, `migration/_migrations.dart`.
Content: exactly §2.
Done when: server boots against a clean database, `\d user_block` shows both indexes and
the `no_self` CHECK, and `SELECT block_hides('U1','U2')` returns false.

**S2 · Drift tables + entities** — depends on S1.
Files: `data/database/table/user_blocks.dart`, `.../user_block_intents.dart`,
`data/database/tentura_db.dart`, `domain/entity/user_block_entity.dart`.
Then `cd packages/server && dart run build_runner build -d`.
Done when: build_runner is clean and `dart analyze` passes. Do not hand-edit `.g.dart`.

### Phase 2 — server data & domain

**S3 · `UserBlockRepositoryPort` + repository** — depends on S2.
Files: `domain/port/user_block_repository_port.dart`,
`data/repository/user_block_repository.dart`.
Implement §6.3/§6.4. The repository touches `user_block` and `user_block_intent` **only** —
no help-offer, forward-edge, or contact writes. `unblock()` **must** capture affected pairs
before deleting.
Done when: `rg "package:tentura_server/data/repository" packages/server/lib/domain` is
empty and a pg test covering T-A1…T-A8 passes.

**S4 · `UserBlockCase` + cleanup orchestration** — depends on S3.
Files: `domain/use_case/user_block_case.dart`, `env.dart` (rate-limit knob),
`.env.example`.
Owns the transaction via `MutatingUnitOfWorkPort` and the cross-repository cleanup (§6.5,
§6.6). Withdrawn help offers are `status == 1` and must go through
`HelpOfferRepositoryPort.withdraw`, never a raw UPDATE.
Done when: unit tests cover self-block rejection, unknown-id rejection, X14, and that a
failure mid-cleanup rolls the block row back.

**S5 · V2 GraphQL API** — depends on S4.
Files: `api/controllers/graphql/mutation/mutation_user_block.dart`,
`.../query/query_user_block.dart`, `_mutations_all.dart`, `_queries_all.dart`.
Blocker id comes from `getCredentials(args).sub` only.
Done when: the operations appear in the V2 schema and a controller test asserts that
passing someone else's id as blocker is impossible.

### Phase 3 — enforcement

**S6 · Migration `m0136` part 1: beacon wall + trigger** — depends on S1.
Files: `migration/m0136.dart`, `_migrations.dart`.
Content: §3.1 and §4.
Done when: T-A3 and T-D1…T-D6 pass.

**S7 · Migration `m0136` part 2: graph, mutual friends, computed fields** — depends on S6.
Content: §3.2, §3.3, plus the SQL for §3.4/§3.5.
Note the `graph_edges_between` signature change — drop the old function in the same
migration.
Done when: `packages/server/test/graph_edges_between_test.dart` is updated and green.

**S8 · Hasura metadata** — depends on S7.
File: `hasura/metadata.json` — computed fields + filters for `user` and `user_presence`,
session argument for `graph_edges_between`.
Done when: Hasura applies the metadata without error and T-H E11/E12 pass.

**S9 · Server-side write guards** — depends on S4.
Files per §7's E2, E4, E5, E6, E7, E14.
Use `UserBlockRepositoryPort.isBlockedPair` / `hiddenPeerIds`; never query the table
directly from a use case.
Done when: one test per guard, asserting both directions.

**S10 · Attention recipient filtering** — depends on S4.
File: `domain/use_case/attention_intent_case.dart`.
Filter **before** the snapshot is recorded — the payload is immutable afterwards.
Done when: T-H E8 passes.

**S11 · Genealogy placeholder** — depends on S4.
File: `data/repository/invite_genealogy_repository.dart`.
Reuse the deleted-account placeholder path; one `hiddenPeerIds` call per fetch.
Done when: T-H E13 passes **including** the structural assertion that D stays reachable
from R.

### Phase 4 — cascade

**S12 · `block_cascade_candidates` verification** — depends on S1.
No new code; a pg test file only, covering T-B1…T-B9, T-C1…T-C4, X2, X3, X4, X11.
Done when: all listed cases pass. **If T-B5 or X4 fail, the CTE guard is wrong — fix
`m0135`, do not weaken the test.**

**S13 · Cascade materialization job** — depends on S12, S5.
Files: `domain/use_case/block_cascade_case.dart`, `task_worker_case.dart`, `env.dart`,
`.env.example`.
Implement §6.7 materialization including the catch-up pass.
Done when: T-B8, T-C2, T-C3, X5, X6, X8 pass.

**S14 · Release sweep** — depends on S13.
Same files.
Done when: T-F1…T-F7 and X10 pass.

### Phase 5 — B3

**S15 · Migration `m0137`: withdrawal gate** — depends on S1.
Files: `migration/m0137.dart`, `_migrations.dart`.
Copy `trust_rebuild_effective_edge` from `m0122` verbatim and change only the published
value per §5.
Done when: T-G1…T-G8 pass. **T-G7 (zero new `trust_evidence_event` rows) is the
regression guard against reintroducing the rejected negative-evidence design.**

**S16 · Wire withdrawal through block, unblock, cascade and release** — depends on S15, S13.
Files: `user_block_repository.dart`, `user_block_case.dart`, `block_cascade_case.dart`.
Withdrawal is unconditional — there is no flag to check. Pass `-1` as the epsilon override
everywhere; skip pairs with no `user_trust_edge` row purely as a cost optimization.
Done when: T-G5, T-G6, T-G8, T-F5, X9 pass.

### Phase 6 — client

**S17 · Client data + domain** — depends on S5.
Files: `features/block/domain/entity/user_block.dart`,
`features/block/domain/use_case/block_case.dart`,
`features/block/data/repository/block_repository.dart`, six `.graphql` files,
`build_client.dart` (operation names).
Then `cd packages/client && dart run build_runner build -d`.
Done when: `flutter analyze` clean and C1 passes.

**S18 · Cubit + state** — depends on S17.
Files: `features/block/ui/bloc/blocked_users_cubit.dart`, `..._state.dart`.
State extends `StateBase`; emit only `state.copyWith(...)` with **new** collection
instances.
Done when: C2 passes.

**S19 · Block sheet** — depends on S18.
File: `features/block/ui/sheet/block_user_sheet.dart` per §8.3.
Use `showTenturaAdaptiveSheet`; no hand-rolled `LayoutBuilder`; all spacing from
`context.tt`.
Done when: C3, C4, C5 pass and `flutter analyze` reports no new design-system lint hits.

**S20 · Blocked list screen** — depends on S18.
Files: `features/block/ui/screen/blocked_users_screen.dart`,
`.../ui/widget/blocked_user_tile.dart`, settings entry, route registration.
`ListView.builder` + `Center`/`ConstrainedBox(maxWidth: tt.contentMaxWidth)`.
Done when: C6 and C7 pass.

**S21 · Profile entry point + blocked-profile rendering** — depends on S19.
Files: `features/profile_view/ui/widget/profile_view_app_bar.dart`,
`.../widget/profile_view_body.dart`.
Done when: menu item toggles Block/Unblock correctly and a blocked profile renders the
stripped view with an Unblock action.

**S22 · l10n + cache invalidation** — depends on S19, S20, S21.
Files: `l10n/app_en.arb`, `l10n/app_ru.arb`, the invalidation wiring per §8.5.
Done when: no hardcoded user-facing strings remain and blocking from the profile
refreshes feed/graph/search without a manual pull-to-refresh.

### Phase 7 — hardening

**S23 · Adversarial suite** — depends on S16, S14.
File: `packages/server/test/data/repository/user_block_adversarial_pg_test.dart`.
Every row of §11 that is not already covered by an earlier subtask: X1, X7, X9, X12,
X13, X15, X16.
Done when: all pass or are explicitly marked `skip:` with the documented accepted-limitation
reason (X1, X15, X16 are expected to be documented rather than fixed).

**S24 · Docs + release note** — depends on S23.
Files: `docs/features/user-block.md` (new, following the shape of
`docs/features/trust_edges.md`), plus a line in `docs/relationship-states.md` explaining
that a person may be hidden by a block.
Done when: the accepted limitations (X1, X15, X16) and the `graph_edges_between` visibility
decision are written down where a future reader will find them.

### Final gate (supervisor, not the implementer)

```bash
cd packages/server && dart analyze && dart test -x pg && dart test -t pg
cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos
cd packages/client && flutter test --dart-define=ENV=test
cd packages/tentura_lints && dart test
./scripts/check-custom-lints.sh          # baseline: client 115, server 0 — must not grow
rg "package:tentura_server/data/repository" packages/server/lib/domain   # must be empty
```

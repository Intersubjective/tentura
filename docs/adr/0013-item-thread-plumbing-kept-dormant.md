# ADR 0013: Item-thread plumbing kept dormant

## Status

Accepted (2026-10-30). Documents an intentional product/engineering choice
recorded for GitHub issue #829. Authority for live behavior remains code;
this ADR is the durable rationale for reviewers and agents.

## Context

Request **discussion** rooms (`beacon_room`, `beacon_room_message`) originally
supported per–coordination-item **item threads**: messages scoped by non-null
`thread_item_id` pointing at a `coordination_item`, with access for room
members plus item participants (creator, target, accepter) who were not
admitted to General.

That product surface was **retired**. Today the **Chat** tab exposes one
conversation per request — **General** (`thread_item_id IS NULL`). Retired
ask, commitment, and blocker item threads are no longer list rows or navigation
targets (see [`docs/features/beacon_room.md`](../features/beacon_room.md)).

Enforcement is layered:

| Layer | Mechanism | Path |
|-------|-----------|------|
| Database | `beacon_room_message_general_only_guard` / `beacon_room_seen_general_only_guard` | `packages/server/lib/data/database/migration/m0254.dart` (and earlier m0193) |
| Application | `DiscussionScopeDisabledException` via `_rejectDisabledDiscussionScope` / `_rejectDisabledScope` | `packages/server/lib/domain/use_case/beacon_room_case.dart`, `packages/server/lib/domain/exception.dart` |
| Product policy | `ProductionDiscussionProductPolicy.generalOnly == true` | `packages/server/lib/domain/policy/discussion_product_policy.dart` |

Despite General-only shipping, the owner **keeps the plumbing on purpose**:
columns, GraphQL args, repository filters, access helpers, and client GraphQL
variables marked `DORMANT(item-threads)` (~20 files; search
`DORMANT(item-threads)` under `packages/`). Sub-discussions inside requests may
return; removing or renaming this machinery would be a large, risky churn for
uncertain gain.

The plumbing **already paid off once**: Request **Questions** (user-facing;
internally the lobby, U088, `coordination_item` kind 7) reuses the same
`thread_item_id` scope and `beacon_room_seen` per-thread watermarks instead of
a separate message table. Migration commentary:
`packages/server/lib/data/database/migration/m0254.dart`. Product spec:
[`docs/features/beacon_questions.md`](../features/beacon_questions.md).

Related historical note: #192 (General-only boundary inventory).

## Decision

**Keep item-thread plumbing dormant.** Do **not** remove, rename, or “clean up”
`thread_item_id` / `threadItemId` parameters, `_canAccessThread`,
`itemParticipantsOnly`, or `DORMANT(item-threads)` markers unless a deliberate
revival or schema migration project explicitly includes them.

No production server registers `InternalMultiThreadDiscussionProductPolicy`;
only tests may use it (`discussion_product_policy.dart`).

## Consequences — live vs dormant

### Live (production)

| Piece | Role |
|-------|------|
| **Questions / lobby scope** | One `coordination_item` kind 7 per request; messages and seen rows use its id as `thread_item_id`. DB guards allow **only** this exception (plus internal test fixture hook `discussion_internal_fixture_allowed()`). |
| **`_canAccessThread` lobby branch** | When `threadItemId` resolves to the request’s Questions item, access follows `questions_access_levels` via `_questionsAccess` (read/write), not room admission. |
| **`_rejectDisabledScope` lobby bypass** | Questions scope is not rejected by `ProductionDiscussionProductPolicy.isDiscussionScopeEnabled`. |
| **Client Questions UI** | Separate from General; may pass non-null scope ids for lobby operations (not “dead client code”). |

### Dormant (intentionally unreachable in production policy)

| Piece | Role |
|-------|------|
| **Item-participant branch of `_canAccessThread`** | After lobby check: if not room member, allow when user is creator/target/accepter of the coordination item (`_isItemParticipant`). Short-circuited when `generalOnly` is true (returns false before item lookup). |
| **Per-item-thread seen watermarks** | `beacon_room_seen.thread_item_id` non-null upsert paths; GraphQL `MarkThreadSeen` with non-general `threadId`; client mark-seen with item scope. Live only for Questions scope id. |
| **`itemParticipantsOnly` in `listThreads`** | `CoordinationItemRepositoryPort.listThreads` filter so non-room viewers could see item threads they participate in; production policy filters list to General only (`beacon_room_case.dart` `listThreads`). |
| **GraphQL / client `threadItemId` for non-lobby items** | Wired through mutations/queries and `beacon_threads_repository.dart`; production clients pass null for General. |
| **Coordination item thread list SQL** | Previews/unread counts for per-item threads in `coordination_item_repository.dart` — unused in General-only product lists. |
| **`InternalMultiThreadDiscussionProductPolicy`** | Test-only proof that repositories still behave when `generalOnly` is false. |

### What is **not** an access leak

Non-null `thread_item_id` on a message does **not** bypass General-only rules
in production: the DB guard rejects inserts/updates except Questions (kind 7);
`_rejectDisabledScope` throws `DiscussionScopeDisabledException` for other
scopes; `_canAccessThread`’s item-participant path is disabled under
`generalOnly`. Questions access is a **separate, audited policy**
(`questions_access_levels`), not accidental item-thread resurrection.

## How to revive item threads (outline)

A revival is a **product + security project**, not a comment deletion:

1. **Policy** — Replace or extend `ProductionDiscussionProductPolicy` (e.g.
   enable non-null scopes, re-enable coordination kinds beyond plan-only).
2. **Database** — Relax or replace `beacon_room_message_general_only_guard` /
   `beacon_room_seen_general_only_guard` for the chosen item kinds; add
   migrations and Hasura review if exposure changes.
3. **Authorization** — Re-audit `_canAccessThread` (lobby branch must stay
   correct), `_canMutateMessage`, `listThreads` / `itemParticipantsOnly`, and
   attention/deep-link paths in `attention_intent_case.dart`.
4. **Client** — Restore thread navigation and non-null `threadItemId` on room
   APIs where appropriate; l10n and design-system review.
5. **Tests** — Extend `general_only_public_contract_test.dart` and boundary
   inventory tests; run pg suites for Questions + any new scopes.

Until then, markers stay; grep `DORMANT(item-threads)` remains the index.

## Rule for reviewers and agents

**Do not** report code tagged `DORMANT(item-threads)` as dead code, unused
parameters, or an access-control leak **without** reading this ADR and
[`docs/features/beacon_room.md`](../features/beacon_room.md) (subsection
*Dormant item-thread plumbing*). Generated GraphQL/DI output is not committed;
absence from a naive grep does not prove removal is safe.

**Do** flag real bugs in the **live** Questions lobby path or missing guard
coverage for new write paths that accept `thread_item_id`.

## References

- Product: [`docs/features/beacon_room.md`](../features/beacon_room.md),
  [`docs/features/beacon_questions.md`](../features/beacon_questions.md)
- Access gate: `packages/server/lib/domain/use_case/beacon_room_case.dart`
  (`_canAccessThread`, `_rejectDisabledScope`)
- Inventory test: `packages/server/test/architecture/general_only_boundary_inventory_test.dart`
- AGENTS.md invariant: Rooms General-only with Questions exception

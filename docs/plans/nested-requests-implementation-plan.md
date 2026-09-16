# Nested requests and General-only discussions — implementation plan

Status: revision 2 — adversarial review round 1 applied; **no implementation performed**. See §11 change log.
Date: 2026-09-06. Live-code baseline: `104786666` plus the working tree.
Source: [architectural proposal](nested-requests-architecture.md). Its older baseline was `ecb9a918c`; use the live paths below.

The product owner explicitly adopted both proposal defaults while this plan was written:

- One-edge hierarchy access exposes ordinary request details, without discussion admission or involvement visibility.
- Hierarchy notices cover entry into Wrapping up, Closed, Cancelled, and Deleted.

Those two choices are settled for this plan. Additional implementation decisions below resolve the proposal's architectural defaults. Implement the specified behavior; do not invent alternate membership, consent, lifecycle, or routing rules. This document authorizes no deployment or database cleanup by itself. The current task produced documentation only.

## 1. Execution contract

This plan is written for an implementer such as Composer 2.5. Execute one numbered task at a time, in order. Complete that task's focused checks and review its diff before proceeding. Keep a companion `docs/plans/nested-requests-implementation-journal.md` with task status, owned paths, commands, results, baseline failures, and the next exact task. Do not mark a gate passed because its tests were skipped.

Paths beginning `S/` below mean `packages/server/lib/`; `C/` means `packages/client/lib/`; `ST/` means `packages/server/test/`; `CT/` means `packages/client/test/`. These are document abbreviations, not directories to create. Paths marked **new** are prescribed additions, not claims that files already exist. Test paths in task acceptance sections are prescribed new tests unless explicitly described as existing.

Before each task, check that its named symbols still exist. Mechanical changes such as allocating the next free migration number are allowed and must be recorded. A changed authorization model, lifecycle producer, schema constraint, or save workflow requires revising this plan against the changed code before implementing that portion. Do not substitute a convenient existing type for a specified domain contract.

Preserve unrelated edits. At plan-writing time `docs/README.md` was already modified and many unrelated plan files were untracked. Do not reset, stash, delete, or stage them broadly. Stage only task-owned paths when implementation is later requested. Do not hand-edit generated Dart, Ferry, Freezed, AutoRoute, Injectable, or Drift outputs.

### Non-negotiable outcomes

1. A child is a normal `Beacon`, with its own owner, membership, help offers, acknowledgement, forwarding, review window, and trust attribution.
2. Parentage is immutable, independent of fork lineage, and never an admission grant.
3. Every admitted parent participant can discover eligible immediate published children. That discovery adds no Inbox/My Work involvement or child unread state.
4. Published requests retain structural identity on deletion. No cascading child lifecycle or deletion.
5. General is the only public conversation on each request. Retain dormant server thread machinery; retire ask/promise/blocker product paths.
6. Plans, plan steps, facts, normal request participation, replies, mentions, polls, attachments, and evaluation remain supported.
7. Hierarchy notices are durable consequences of source transitions, never new lifecycle transitions themselves.

## 2. Live-code map and implementation implications

| Current responsibility | Inspected owner | Required change |
|---|---|---|
| Normal create, draft publish, media, fork, cancel, delete | `S/domain/use_case/beacon_case.dart`: `create`, `publishDraft`, `fork`, `beaconCancel`, `deleteById` | Extract reusable create validation/persistence collaboration; route child draft publication through hierarchy validation; keep fork separate. |
| Client fields → stage → media reconciliation | `C/domain/use_case/beacon_create_case.dart`: `BeaconSaveCommand`, `BeaconSaveFailure`, `_save`, `_reconcile`; `C/domain/port/beacon_write_port.dart` | Extend the existing orchestration with typed creation context and durable command identity. Preserve canonical IDs and staged image IDs on failure. |
| Beacon writes and row locks | `S/domain/port/beacon_repository_port.dart`; `S/data/repository/beacon_repository.dart` | Keep SQL in data. Existing `runInBeaconStateTransaction` and `recordBeaconStatusTransition` are integration points, not permission to create independent commits. |
| Mutating transaction and attention | `S/domain/port/mutating_unit_of_work_port.dart`; `S/data/repository/mutating_unit_of_work.dart`; `S/domain/use_case/transactional_attention_case.dart` | Hierarchy event/target writes must use the same `TenturaDb` transaction, including actor attribution. |
| Scheduled image task queue | `S/data/service/task_worker.dart`; `S/data/repository/tasks_repository.dart` | `TaskWorker.create` opens a separate PostgreSQL connection. Do not use this queue as the atomic hierarchy outbox. |
| Existing recurring sweeps | `S/domain/use_case/task_worker_case.dart` | Schedule a bounded hierarchy delivery sweep beside attention delivery/expiry sweeps. |
| Close and review finalization | `S/domain/use_case/evaluation_case.dart`; `S/domain/use_case/evaluation/review_finalization_case.dart`; `S/domain/use_case/attention_expiry_sweep_case.dart` | Cover immediate close, review opening, early finalization, automatic expiry, and all callers of `closeAndFinalize`. |
| Read policy | `S/domain/beacon_visibility.dart`; `S/domain/port/beacon_access_guard.dart`; `S/data/repository/beacon_access_repository.dart` | Add two non-recursive content-read facts; preserve separate involvement predicate. The adapter currently delegates to SQL functions. |
| Canonical SQL and Hasura | migrations `m0123.dart`, `m0136.dart`; `hasura/metadata.json` | Replace current function definitions in a new migration. Metadata is wrapped under `metadata`, not a top-level `sources` key. |
| Room/thread authorization | `S/domain/use_case/beacon_room_case.dart`: `_canUseRoom`, `_canAccessThread`, `_canMutateMessage`, list/target/seen/message methods | `_canUseRoom` recognizes author, steward, or `roomAccess == admitted`; item participation must no longer grant a public conversation path. |
| Promotion and surviving item persistence | `S/data/repository/coordination_item_repository.dart`; `S/data/database/table/coordination_items.dart` | New child provenance must not use `linked_item_id` or replace plan records. |
| Status audience | `S/data/repository/beacon_room_notification_context_repository.dart`; `S/domain/entity/beacon_notification_context.dart`; `S/domain/use_case/attention_intent_case.dart::requestStatusChanged` | `usersWithActiveCoordination` currently derives from item creator/target/acceptor. Replace its retired-item dependency with retained participation facts. |
| Account erasure | `S/domain/use_case/user_case.dart::deleteById`; `S/data/repository/user_repository.dart::deleteById`; `m0001.dart` | Existing `beacon_user_id_fkey` uses `ON DELETE CASCADE`. Preserve structural rows before deleting an owner. |
| Discussion UI | `C/features/beacon_threads/ui/widget/threads_list.dart`; `ui/bloc/threads_cubit.dart`; `ui/widget/thread_host.dart`; `ui/bloc/thread_host_cubit.dart` | Replace semantic item rows with child cards; preserve General room state and read-watermark behavior. |
| Composer / promotion UI | `C/features/beacon_create/ui/bloc/beacon_create_cubit.dart`; `ui/screen/beacon_create_screen.dart`; `C/features/beacon_view/ui/widget/coordination_item_composer_sheet.dart`; `C/features/beacon_threads/ui/widget/room_message_tile.dart` | Reuse the request composer. Retain supported plan interactions outside the retired target picker. |
| Navigation / transport | `C/app/router/root_router.dart`; `C/app/router/browse_deep_link.dart`; `C/data/service/remote_api_client/build_client.dart` | Child navigation uses normal Beacon routes. New V2 operation **document names** require explicit direct-routing registration. |
| Realtime | `docs/contracts/realtime-entity-contract.json`; `DEV_GUIDELINES.md` § Realtime projection convergence | Add a hierarchy projection kind and access-revocation/catch-up tests; no projection data in its wire hint. |

Latest migration inspected: `m0153`. Current client version: `6.16.4`; default minimum: `6.12.16`. Proposed release is `7.0.0`, subject only to rebasing onto a newer version before release.

## 3. Frozen behavior and exact contracts

### 3.1 Structure, drafts, fork, deletion

- Add `beacon.parent_beacon_id text NULL`, FK to `beacon(id)` with `ON DELETE RESTRICT`, immediate checking. Never use lineage columns for nesting.
- Parentage is assigned only on insertion, including insertion of a private child draft. Every update changing it, including `NULL → id` and `id → NULL`, is rejected by the database. No public update input contains parentage.
- A parent must already exist and be published; terminal eligibility is checked by the creation command. Reject self-parenting and cycles defensively in the insert trigger. No parentage changes are available to a draft owner either.
- A child draft is author-only, never a hierarchy list/count/event/recipient. Its intended parent and source are visible only through its owner's draft response. A draft cannot itself be a parent.
- Parent `BeaconStatus.allowsCoordination` is the creation/publication gate: open-family and Wrapping up allowed, Closed/Cancelled/Deleted/draft denied. Apply blocks and effective admission as additional conditions.
- `beaconFork` keeps existing copy/lineage semantics. Forking a child produces a standalone draft with lineage to the source and **no nesting parent**. Do not copy promotion provenance.
- Deleting a private draft may hard-delete it and its command/provenance records according to §3.4. Deleting a published request preserves its Beacon row and immutable parent ID as a deleted tombstone. Descendants are unaffected.
- No roll-up completion, depth limit, reparenting, detachment, or attachment of an existing request. The UI loads one edge at a time.

### 3.2 Authorization matrix

Superseded by issue-146 shared-context visibility architecture (D1/D2).

Define `effectiveAdmission(B,U)` from existing author/steward/admitted participant facts, after the existing request-author block check. Do not derive it from `canReadContent`, a help offer alone, a forward, an Inbox row, or cached navigation.

Add two facts to content visibility: `isAdmittedToImmediateParent` and `isAdmittedToImmediatePublishedChild`. Compute them directly from participants/ownership/stewardship on that adjacent request. They must not recursively invoke content-read functions. The adjacent grantor must not be a draft or deleted request; closed/cancelled admission can still grant a link read while ordinary retained access permits it.

**One-edge grants must not widen `canReadContent`.** The canonical `beacon_can_read_content` / `BeaconAccessGuard.canReadContent` predicate is today the *sole* authorization gate in front of several mutations and privileged reads, so adding hierarchy reasons to it silently confers write authority the matrix below denies:

| Consumer | Effect if hierarchy reasons enter `canReadContent` |
|---|---|
| `S/domain/use_case/help_offer_case.dart` (`canReadContent` then `status.isOpenFamily`) | Parent-only admittee could offer help on the child. |
| `S/domain/use_case/forward_case.dart` (`canReadContent` then `allowsForward`) | Parent-only admittee could forward the child. A forward edge is itself a content-read grant inside `beacon_can_read_content`, so this **mints child access for arbitrary third parties** and breaks non-negotiable outcome 2. |
| `S/domain/beacon_lineage_visibility.dart::assertBeaconLineageSourceVisible` | Parent-only admittee could fork the child as a lineage source. |
| `S/domain/use_case/invitation_case.dart` | Parent-only admittee could issue child-scoped invitations. |
| `S/domain/use_case/coordination_case.dart::helpOffersWithCoordination` | Discloses who offered help on the child (admission fields are redacted, membership is not). |

Therefore introduce a **separate, narrower predicate** for hierarchy-linked detail — `beacon_can_read_linked_detail(beacon, viewer)` / `BeaconAccessGuard.canReadLinkedDetail` — carrying exactly the two one-edge facts, and leave `canReadContent` semantically unchanged. Only the child-card, child-detail, and parent-reference read projections consume the new predicate. Task 00 must enumerate every current `canReadContent` caller; Task 03 must prove by test that none of the five consumers above changes behaviour for a hierarchy-only viewer. Reuse the existing `canReadTombstone` guard method for the deleted-child card rather than adding a third tombstone path. If a future surface genuinely needs the union, it must opt in explicitly at its own call site, never by widening the shared predicate.

| Operation | Rule |
|---|---|
| Child list and create capability on P | Effective admission to P; apply P's content/tombstone and block restrictions. |
| Normal content of C | Existing content rule OR effective admission to C's immediate non-deleted published parent. |
| Normal content of P from a child | Existing content rule OR effective admission to one immediate non-deleted published child of P. |
| Discussion/People/private facts/reviews/actions on C | C's existing independent policies. No hierarchy role added. |
| Inbox/My Work/profile involvement graph | Existing explicit involvement predicates only. |
| Deleted child card | Generic structural tombstone only for admitted parent viewers who are not blocked by the known child owner. Never normal deleted content. |
| Parent reference on readable child | `none` if standalone; `available` only when parent content is independently authorized under the one-edge rule; otherwise `unavailable`, with no title/owner or actionable ID. Deleted parent uses generic unavailable/tombstone wording. |

Ordering: block restriction → target draft/deleted restriction → ordinary access and one-edge reasons. Nullable erased owner means there is no owner profile to disclose, not a bypass allowing normal tombstone reads.

Example fixture used throughout tests: A → B → C, plus A → D. Alice admitted only to A can read B and D details but cannot list B's children, read C, or open B/D General. Carol admitted only to C can read B details but not A. Bob owns B; his rights on A and C are independent. Revocation removes only the corresponding hierarchy grant; ordinary forwarding/help/admission may keep access.

### 3.3 Public domain values and ownership

Create these shared pure values under root `lib/domain/entity/` (use root `BeaconStatus`; no GraphQL/Drift imports):

| New file | Value and fields |
|---|---|
| `beacon_creation_context.dart` | Sealed `BeaconCreationContext`: `standalone`, `child(parentBeaconId)`, `promotedChild(parentBeaconId, sourceMessageId)`. It contains no fetched message body or media. |
| `beacon_hierarchy_summary.dart` | `BeaconHierarchySummary`: `beaconId`, nullable `title`, nullable owner summary (`id`, permitted display name/avatar reference), `status`, immutable `publishedAt`, `isTombstone`. Tombstones have no title/owner/media. Ordinary cards use existing safe avatar resolution. |
| `beacon_parent_reference.dart` | `BeaconParentReference`: state `none/available/unavailable`, nullable `beaconId`, nullable title. Only `available` carries navigable data. |
| `beacon_promotion_source.dart` | `BeaconPromotionSource`: source Beacon/message IDs, authorized current text preview, source author summary. Composer-only authorized value, never a child content field. |
| `beacon_hierarchy_page.dart` | `BeaconHierarchyPage`: summaries, nullable next cursor. No unrestricted count or ancestor list. |
| `beacon_hierarchy_capabilities.dart` | `canListChildren`, `canCreateChild`, nullable denial code. Results are hints; commands revalidate. |
| `beacon_hierarchy_event.dart` | Typed source transition and delivery direction `ancestor/child`; stable event ID, per-source sequence, source ID, from/to status, optional actor ID, occurredAt. No request title/message text. |

New server ports under `S/domain/port/`: `beacon_hierarchy_repository_port.dart` (read projections/structural facts and mutation locks), `beacon_hierarchy_command_port.dart` (idempotency/provenance persistence), `beacon_hierarchy_outbox_port.dart` (record event and set-based targets, claim/materialize work). Use typed results, never a public `Map<String,dynamic>` API. Server-only storage records live under `S/domain/entity/`, including a nullable-author `BeaconStructuralRecord` for tombstones.

New client `C/domain/port/beacon_hierarchy_port.dart` exposes `capabilities`, `listChildren`, `parentReference`, `promotionSource`, and `createChildDraft`. The data adapter is `C/features/beacon/data/repository/beacon_hierarchy_repository.dart`, with `.graphql` inputs and DTO mappers in that feature's `data/gql/` and `data/model/`. A new `C/domain/use_case/beacon_hierarchy_case.dart` coordinates this port, the existing create use case, and realtime. Widgets/Cubits never call remote services or another feature's repository directly.

New server cases: `BeaconHierarchyCase` (reads/capabilities), `BeaconChildCreateCase` (authorized creation/publication), `BeaconLifecycleEffectsCase` (pure eligibility plus durable event recording), `BeaconHierarchyDeliveryCase` (bounded delivery). A `BeaconCreationPolicy` extracted from `BeaconCase` owns shared normalization/validation. Cases use domain ports and the existing unit of work; repositories own SQL.

### 3.4 Creation protocol and idempotency

Use one server command for new child creation, supporting direct published creation and private drafts. Current client always creates a **draft first**, reconciles media using the existing save flow, then publishes when the user requested publication. This ensures a visible card never advertises unfinished media. Standalone save semantics remain unchanged.

1. Composer opening creates a UUID `clientCommandId`, retained for that logical creation attempt across retries and restored draft state. It is not a Beacon ID. A reopened existing draft uses its canonical Beacon ID.
2. `beaconChildCreate` receives parent/source context, normal creation fields, `clientCommandId`, and `draft`. It does not accept multipart media; media is staged after canonical draft creation through existing commands. Direct API published creation can have no media and later use normal media edits.
3. Scope idempotency by `(actorUserId, clientCommandId)`. Hash the canonical normalized input, including parent/source/draft and fields, excluding uploaded bytes. Same key + same hash returns the canonical prior result after current authorization checks. Same key + different hash returns `BEACON_CHILD_COMMAND_CONFLICT`.
4. On ambiguous creation failure, retry the exact saved command before submitting edited fields. Once the ID is recovered, apply edits through ordinary draft updates. The client must not silently mint another key in response to a timeout.
5. Creating a promotion draft stores private provenance but does not reserve the source's visible publication link. Several users may hold private drafts; at most one may publish for a source. A partial unique index on published provenance enforces this.
6. Concurrent publication attempts for the same source return `BEACON_SOURCE_ALREADY_PROMOTED`, carrying the existing child ID only if currently readable. No second published child or parent notice is committed. The losing draft remains private and editable/deletable; it cannot be detached or turned into a direct child through an update.
7. A retry of the winning command returns that same child. A fresh duplicate published promotion command may resolve to the existing child without copying new fields into it. Return result discriminator `created/replayed/alreadyPromoted`; the client never treats `alreadyPromoted` as successful publication of its own draft.
8. Publication uses the existing `beaconPublish` GraphQL mutation (client document `BeaconPublish`; the domain method behind it is `BeaconCase.publishDraft` — do not confuse the two names). `BeaconCase.publishDraft` reads immutable creation context and delegates children to `BeaconChildCreateCase.publishDraft`; ordinary drafts retain their existing branch. Validate owner plus parent admission/lifecycle/blocks and current source accessibility again.
9. Source validation requires an existing non-deleted, ordinary human-authored **General** message belonging to the claimed parent. Another author's message is allowed. For v1 eligibility requires a real author, null thread scope, no system/event payload, no semantic marker, no linked coordination item/event, and no linked polling/system object. Text and ordinary attachment messages qualify; an empty body is allowed but the user must supply normal required child fields. Reject system/coordination/admission/hierarchy events, including the existing blocker/needInfo/done rich-action exclusions. Put these predicates in one shared promotion eligibility policy and test the same fixtures on client and server; source access alone is insufficient.
10. Seed editable child description from the source's current text only. Title starts empty, since normal request title is required. Source quote stays in composer UI. Copy no attachments, replies, mentions, participants, targets, facts, or help offers. Edited source text never rewrites child text.
11. Successful publication atomically commits status/parent/provenance, one parent General creation notice, and any normal General-message attention recording. Draft creation emits no parent notice/attention. Direct creation has the same notice with no source footer.
12. Return the canonical child Beacon ID and ordinary saved Beacon fields. Media failure remains `BeaconSaveFailure` with draft ID, completed stages, and a new `publish` phase when publication fails. Retry must neither re-create nor discard completed uploads.
13. Keep an idempotency tombstone after deleting a draft: a replay reports `BEACON_CHILD_COMMAND_GONE`, never re-creates it. A new explicit composer session may use a new key. Private command responses/provenance can be scrubbed while retaining the actor/key/hash/deleted marker for the account lifetime; erase them with account deletion.

Creation notice payload is versioned: `{version:1, kind:"childCreated", childBeaconId, sourceMessageId?}`. Store no source body. General source-message projection obtains its authorized child footer via the provenance join; do not put child IDs in `linked_item_id`. On source deletion set provenance message reference to null and remove source navigation from notices; the child remains. General creation notice uses ordinary parent-discussion message attention rules, with actor suppression for attention and actor visibility in chat. It does not subscribe anyone to child attention.

### 3.5 API surface

Use V2 GraphQL through existing controllers/schema registration. Exact field and client document names:

| V2 field | Client document | Inputs → result |
|---|---|---|
| `beaconHierarchyCapabilities` | `BeaconHierarchyCapabilities` | `beaconId` → capability value |
| `beaconChildren` | `BeaconChildren` | `parentBeaconId`, `group` (`active/finished/deleted`), `first` (default 20, 1–50), nullable `after` → page |
| `beaconParentReference` | `BeaconParentReference` | `beaconId` → guarded reference |
| `beaconPromotionSource` | `BeaconPromotionSource` | `parentBeaconId`, `sourceMessageId` → composer-only source value |
| `beaconChildCreate` | `BeaconChildCreate` | ordinary required create fields + `parentBeaconId`, optional `sourceMessageId`, `clientCommandId`, `draft` → `{outcome, beaconId, beacon}`; `beacon` nullable only for authorized conflict/unavailable outcomes as specified |
| existing `beaconPublish` | existing `BeaconPublish` | existing draft ID → existing canonical Beacon shape; child branch enforces §3.4 |

`active` includes open-family + reviewOpen; `finished` includes closed/cancelled; `deleted` includes generic tombstones. Group pages have independent cursors. Order within each group is immutable `published_at DESC, id DESC`. `published_at` is set once at publication; backfill existing published rows from `created_at`, drafts null. Add a partial parent/publication index. Cursor is opaque, versioned base64url data containing parent/group/publication timestamp/ID; validate all fields and context, reject invalid cursors with `BEACON_HIERARCHY_CURSOR_INVALID`. Cursor is no capability: authorize every call and filter before limiting. No total count in v1. State changes between pages may move groups; refresh resets pages and deduplicates by Beacon ID.

Error codes added through existing exception/code mapping: `BEACON_CHILD_CREATE_FORBIDDEN`, `BEACON_PARENT_NOT_COORDINATABLE`, `BEACON_PROMOTION_SOURCE_INVALID`, `BEACON_SOURCE_ALREADY_PROMOTED`, `BEACON_CHILD_COMMAND_CONFLICT`, `BEACON_CHILD_COMMAND_GONE`, `BEACON_HIERARCHY_CURSOR_INVALID`, `DISCUSSION_SCOPE_DISABLED`, `COORDINATION_KIND_DISABLED`. Unauthorized/missing source and parent IDs must use non-enumerating responses consistent with existing access errors. Do not disclose a conflicting child ID before authorizing it.

Keep the existing public thread list/message operations as General-only compatibility facades. Remove named retired coordination mutations from public schema in the breaking release; retain explicit domain rejection as defense against internal/alternate invocation. A supplied non-General scope is rejected, never normalized to General. New hierarchy queries do not accept arbitrary thread IDs.

## 4. Persistence, locks, and durable lifecycle delivery

### 4.1 New storage

At the inspected baseline allocate these additive migrations; renumber together only if occupied at implementation time. **A migration is immutable once any database has applied it.** `migrant` gates on the highest recorded `schema_version`, so SQL appended to an already-applied version silently never runs — existing migration tests delete `schema_version` rows specifically to work around this. The table below is therefore an allocation *floor*, not a licence to amend: any task that needs further SQL after its migration may have been applied allocates the **next free migration number** instead of editing an earlier one. Concretely, the realtime publisher SQL in Task 14 and the General-only persistence protection in Task 07 each take their own new migration rather than being folded back into `m0155`/`m0156`. Record every allocation in the journal. Register handwritten migrations in `S/data/database/migration/_migrations.dart`; do not edit old migrations or use client Drift migration generation for server SQL.

| Migration | Contents |
|---|---|
| `m0154.dart` | parent/publication columns, immutable-parent/cycle constraints, indexes; child command and promotion tables; lifecycle event and delivery outbox tables (incl. lease columns); `beacon_room_message.author_id` nullability + `ON DELETE SET NULL` + system-message discriminator, which Task 06's worker depends on (Task 02 only). |
| `m0155.dart` | one-edge read + `beacon_can_read_linked_detail` functions, effective-admission helper; private-table permissions; lock helper/triggers required by §4.2 (Task 03 only). |
| `m0156.dart` | General-only persistence protection and the lifecycle write guard's DB-side support (Task 07 only). |
| `m0157.dart` | account-erasure/tombstone FK change on `beacon.user_id` and the retained-user-reference dispositions from §4.5, supporting constraints (Task 08 only). |
| `m0158.dart` | scoped irreversible legacy cleanup after the audited manifest is complete; no unrelated data reset (Task 09 only). |
| `m0159.dart` | hierarchy realtime publishers/recipient functions (Task 14 only, before release). |

Each row is owned by exactly one task, so no migration is ever amended after a database has applied it.

New table definitions in `S/data/database/table/`, registered in `tentura_db.dart`:

- `beacon_child_commands.dart`: actor/key composite uniqueness, normalized input hash, nullable result Beacon ID, result state, timestamps. Result FK may become null only for a deleted private draft; preserve command-gone marker. Do not expose this table through Hasura.
- `beacon_promotions.dart`: child ID PK/FK, parent ID FK, nullable source message FK `ON DELETE SET NULL`, nullable promoter attribution, nullable `published_at`. Unique non-null source ID **where published_at IS NOT NULL**. Match child.parent to parent and source.beacon to parent in repository validation and DB constraint trigger. Message must have null thread scope. No source body snapshot.
- `beacon_hierarchy_events.dart`: event ID PK; source Beacon FK RESTRICT; per-source sequence; from/to status; event timestamp; nullable actor attribution. Unique `(source_beacon_id, source_sequence)`. Source Beacon stores a monotonically increasing hierarchy event sequence updated under its lock. Reopen can be local, but a later close receives a new sequence/event.
- `beacon_hierarchy_deliveries.dart`: event ID + target Beacon ID PK; direction; state (`pending/leased/delivered/suppressed/parked`); attempt count; next attempt; last safe error code; nullable notice ID; completion timestamp; **`lease_owner` and `lease_until`**. FK targets RESTRICT. Due-work index on due state/next attempt. No per-user recipients until materialization. States `delivered`, `suppressed`, and `parked` are terminal. Model the lease on the existing fenced pattern in `S/data/repository/attention_channel_delivery_repository.dart`, which already leases with `lease_owner`/`lease_until` and performs owner-qualified updates; do not invent a second scheme.

The creation notice has independent uniqueness keyed by child ID (`child_created:<childId>`), enforced by a dedicated unique notice identity column/index on `beacon_room_message`. Hierarchy lifecycle notice identity is `hierarchy:<eventId>:<targetId>`. Add nullable identity for system messages; leave ordinary messages unchanged. Event JSON is typed/versioned on both sides; nullable identity is not a general caller-supplied public message field.

### 4.2 Transaction and lock protocol

Choose a deliberately simple initial serialization mechanism: one transaction-scoped PostgreSQL advisory mutex identified by `hashtextextended('tentura.beacon_hierarchy.v1', 0)`. Implement it through `BeaconHierarchyRepositoryPort.lockMutationScope()` in the data adapter. It serializes short hierarchy-sensitive database mutations; it must never encompass uploads, HTTP, push/email, or worker sleep. Document this throughput tradeoff; replacing it with root-scoped locks is a separate measured optimization.

Every child create/publish, relevant lifecycle transition, admission/steward removal/grant, request-owner block/unblock, source message delete, and account erasure takes this mutex **before existing row locks**. This includes standalone lifecycle paths so a concurrently publishing descendant cannot fall into a gap. Identify callers in Task 00 and modify the command entry transaction, not a helper invoked after locking a row. Use one existing `MutatingUnitOfWorkPort` transaction; nested collaborators join that transaction and never open a separate connection.

Within the mutex: lock involved Beacon rows sorted by ID, then admission/provenance/source-message rows, then command record. Recheck authoritative facts after acquiring locks. Idempotent lookup may occur optimistically, but acceptance is under the transaction. Retry deadlock/serialization conflicts at the outer command boundary with the same command identity, at most three attempts; surface a retriable error afterward. Domain failures are not retried automatically.

The delivery worker takes only its delivery-row lock and target transaction locks; it does **not** take the global hierarchy mutex or change Beacon statuses. It must not acquire a source lifecycle row lock while holding a target row lock. Immutable event/topology records suffice for notice materialization. Source transitions insert deliveries but never wait on existing delivery rows. Verify this separation with concurrent-worker tests. Restrict Beacon mutation-lock triggers to hierarchy/lifecycle/ownership columns; a notice's ordinary timestamp/counter maintenance must not acquire the global mutex indirectly.

Database-facing alternate writers must not evade invariants: parentage triggers reject updates; General-only public DB writes are rejected; authorization-changing supported SQL paths share the mutex using a BEFORE STATEMENT trigger/helper before rows are locked. Inventory the actual tables, including `beacon`, participant/steward, block, and source-message delete paths. Do not pretend a BEFORE ROW trigger establishes the prescribed lock order. If a direct writer is not a supported product path, revoke its role permission rather than broadening its API. Dormant thread fixtures use a separate test-only role/transaction capability, unavailable to the runtime role.

### 4.3 Source lifecycle event algorithm

Inside the transaction that commits an actual eligible transition:

1. Hold §4.2 mutation scope and source row lock; establish the actual previous/new status and original committed event time. Do nothing for no-op transitions or draft deletion.
2. Increment source sequence; create one immutable hierarchy event. Use its stable ID in related new occurrence identities. Ordinary source-request status/trust effects continue exactly once.
3. Insert target work with a **single set-based recursive SQL traversal** of immutable parent edges: every published descendant at all depths plus the source's immediate parent if published. Exclude the source. Deduplicate by `(event,target)`. Direction is `ancestor` for descendants and `child` for immediate parent.
4. Traverse through deleted/closed/cancelled intermediate nodes. Unpublished drafts are not targets and cannot have descendants. Include deleted destinations in delivery bookkeeping so they can be suppressed explicitly.
5. Commit source state, event, target set, activity record, and existing source attention together. Any failure rolls all back. There is no post-commit best-effort hierarchy enqueue.

The SQL statement snapshot taken after acquiring the mutation mutex defines the affected published descendants. A child published later gets no historical delivery. Wrapping up → Closed creates two events, while opening a review window produces no premature Closed event. Reopening is local and creates no hierarchy notification; a later eligible transition is a new event.

Producer ownership is exact: `BeaconCase.beaconCancel` and published `deleteById`; `EvaluationCase.beaconClose` (immediate closed branch and reviewOpen branch); `ReviewFinalizationCase.closeAndFinalize` **only when `didClose`** for final Closed. `EvaluationCase.closeNow`, `EvaluationCase._autoCloseReviewWindow`, and `AttentionExpirySweepCase.runDue` call that finalizer and must not record another hierarchy Closed event. `EvaluationCase._ensureExpiredClosed` invokes the expiry sweep; read-triggered expiry therefore follows the same durable path. `reopenFromReview` and `extendReviewWindow` do not emit hierarchy notices. Any other status writers discovered in the inventory must either call the same effects collaborator or be explicitly demonstrated ineligible. Do not put hierarchy effects in a generic status setter that would also fire for replay/repair/import. New hierarchy effects/outbox collaborators are required production dependencies; update test constructors with fakes instead of allowing a nullable dependency to silently omit effects.

### 4.4 Worker and attention algorithm

Add the sweep to `TaskWorkerCase`, initially at the existing attention-delivery cadence, batch limit 50. For each target, use a separate transaction and `FOR UPDATE SKIP LOCKED`. Select only due pending rows with **no earlier pending event sequence for that source/target pair**. A failed predecessor blocks later events for that pair, not unrelated sources/targets. This preserves source-event order even across workers. Show original event timestamp in the notice; do not backdate the message insertion timestamp used by unread watermarks.

Within the target transaction:

1. Load immutable event and current destination structural state. A deleted/missing permitted destination is completed as `suppressed`, with no chat/attention, while descendants already have their own work rows.
2. Insert/reuse the General system notice by unique notice identity. Closed/cancelled destination discussions may receive internal system events even though user message writes are disabled by the new guard in §5.2.

   **System authorship is a prerequisite, not an assumption.** `beacon_room_message.author_id` is today `NOT NULL` *and* `ON DELETE CASCADE` to `user(id)` (`m0036`). Neither available option works as-is: automatic expiry has a null actor (`AttentionExpirySweepCase.runDue`), so there is no account to attribute; and attributing to a real actor both leaks that actor's ID, display name and avatar through the ordinary message projection — contradicting the person-free notice contract below — and lets that account's later erasure CASCADE-delete already-delivered notices while their delivery rows still read `delivered`, with no rematerialization path. Therefore `m0154` must forward-migrate `beacon_room_message.author_id` to nullable with an `ON DELETE SET NULL` user FK, add a system-message kind discriminator, and constrain `author_id IS NOT NULL OR <message is system-authored>` so ordinary user messages still require a real author. The message projection and its GraphQL type must render a null author as the generic system identity, never as an empty or session-equal user. Prove with a test that erasing any account leaves delivered hierarchy notices intact and their delivery rows consistent.
3. Resolve the destination's current ordinary status audience; create one typed `AttentionEventType.beaconHierarchyStatusChanged`. Reuse status preferences, priority, watcher channel policy, actor suppression, block handling, and batching. Its source/subject request for authorization and destination URL is the **receiving** request.
4. Record the notice, immutable recipient snapshot, occurrence/receipts/channel jobs via the existing attention dispatcher; mark the hierarchy delivery delivered in the **same transaction**. Attention occurrence key is `hierarchy:<eventId>:<targetId>`.
5. On crash/failure before commit, rollback all target effects. On retry after commit, delivered state/unique identities prevent duplicate effects. A channel-delivery retry uses the already stored occurrence payload and recipient snapshot; it never recomputes them.

Retry transient target failures with capped exponential delay: 5 seconds doubling to 1 hour, attempt count and safe error code persisted. Log event/target IDs, attempts, oldest pending age, batch successes/failures/suppression counts without source text. Do not silently discard work or skip predecessors.

**Claim fencing.** A worker claims a due row by moving it `pending → leased`, stamping `lease_owner` (its own worker identity) and `lease_until`, inside the claim transaction. Rows are due when `pending` and `next_attempt <= now`, **or** `leased` with an expired `lease_until` (crash recovery). Because failure scheduling is recorded in a separate short transaction *after* the materialization transaction rolls back, the row lock is already gone by then — so that failure update, and every terminal transition, must be **owner-qualified**: `WHERE event_id = ? AND target_id = ? AND state = 'leased' AND lease_owner = ?`. Without this fence a stale worker can overwrite a row another worker has since `delivered`, corrupting terminal state and re-blocking later events for that pair. The unique notice identity and attention occurrence key still prevent duplicate user-visible notices, so the failure mode is terminal-state corruption and redundant materialization, not duplicate chat or attention.

**Poison escape hatch.** Because a failed predecessor blocks later events for its (source, target) pair, an irreparable delivery would otherwise wedge that pair forever. After 10 failed attempts the row alerts and stops being selected as ordinary due work; an audited operator action may move it to terminal `parked` with the recorded safe error code, which unblocks strictly later events for that pair while leaving a durable record that one notice was never delivered. `parked` is deliberately distinct from `suppressed` (which stays reserved for deleted/missing destinations) so the two are never conflated in metrics. Parking is an explicit, logged, authorized operation — never automatic and never silent.

Status audience facts become explicit `activeHelpOfferUserIds`, `activeRequestParticipantUserIds`, and `activePlanParticipantUserIds` alongside author/steward/admitted/Inbox-stance facts. Use existing active help-offer and acknowledged-participation state projections; do not reinterpret ask/promise state as commitment. Surviving published active plan creator/target/acceptor can contribute the last set. Existing status notifications and hierarchy status notifications share the same recipient-selection policy.

Shared chat/push text is safe for every destination viewer: “An ancestor request entered Wrapping up”, “A child request was closed”, etc. Include status and original date, no source title/body/person names. Source deletion uses generic deleted wording. Rendering may resolve an authorized source link separately; inaccessible source stays plain text. Notification navigation always opens the destination's General notice, not a source link that may be inaccessible. General notice includes the actor's session even when actor attention is suppressed. Never invoke destination evaluation or lifecycle commands.

### 4.5 Erasure and structural tombstones

Choose nullable authors on deleted structural rows, rather than introducing a fake account.

**Retained user references must each get an explicit disposition.** `UserCase.deleteById` currently deletes owned images and then the user row directly. Several tables reference `public.user(id)` in ways that block or destroy supported history, and the erasure contract is not implementable until each is decided and tested:

| Reference | Current FK action | Required decision |
|---|---|---|
| `beacon_fact_card` pinner (`m0039`) | `ON DELETE RESTRICT` | Explicitly blocks deletion today; must be nulled/anonymised before the user row is removed. |
| Admission-event actor (`m0113`) | no action (default `NO ACTION`) | Blocks deletion; anonymise attribution, retain the event. |
| Commitment-event actor (`m0139`) | default `NO ACTION` | Blocks deletion; anonymise attribution, retain the event. |
| Plan creator / target / acceptor (`m0064`) | default `NO ACTION` | Blocks deletion; plans are supported and must survive with anonymised attribution. |
| Help-response author (`m0022`) | default `NO ACTION` | Blocks deletion; retain help state with anonymised attribution. |
| `beacon_room_message.author_id` (`m0036`) | `ON DELETE CASCADE` | Silently destroys history including delivered hierarchy notices; see §4.4 step 2. |

Task 00's manifest must enumerate every `public."user"(id)` reference with its actual `pg_constraint` action and assign each one of: nullable-and-anonymise, scrub-then-delete, or cascade-is-correct. No category may be left to implementer discretion. Then:

1. Forward-migrate `beacon.user_id` to nullable, replace its user FK with `ON DELETE SET NULL`, and constrain `user_id IS NOT NULL OR status = deleted`. Non-deleted requests must always have a real owner. Update the Drift declaration and structural mapper; normal content projections still require a non-null owner.
2. Refactor account deletion to one domain-owned erasure transaction: acquire hierarchy mutation scope; find the account's owned published requests; transition them to deleted and record hierarchy effects; scrub personal request content/media references using the established deletion/GC mechanisms; delete private drafts; then remove the account and let owner FKs become null. Use generic non-personal placeholder strings satisfying existing title/description CHECK constraints, clear optional context/location/tags/needs/media metadata, and clear primary-need/cover references consistently. Those storage placeholders are never normal readable content. Test the complete scrub against the live constraints rather than disabling constraints for erasure.
3. Preserve all published owned Beacon identities/parent IDs, including intermediate nodes. Remove only the erased user's participation from independently owned descendants according to ordinary erasure policy. Never cancel/delete those descendants.
4. Image/blob cleanup is durable GC work; no object-store delete is performed inside the DB transaction. Review current `UserCase.deleteById` ordering (`deleteAllOf` before user delete) and adapt it so a failed relational mutation does not leave content references pointing at deleted objects.
5. Newly added promoter/actor attribution follows erasure policy (nullable FK or separately scrubbed attribution); event identity, sequence, status, timestamps, and topology survive without copied personal content. Completed attention payloads are handled by existing account-attention erasure rules; pending hierarchy events resolve a deleted actor as system/unknown and contain no actor name.
6. Normal Beacon content queries exclude deleted rows before mapping required author data. Tombstone navigation uses `BeaconStructuralRecord`/hierarchy projection, not a fake empty normal Beacon. Existing full-entity loaders used by delete/no-op paths must explicitly handle a structural row. Do not weaken author checks to equate null/empty IDs to the session.
7. Alternate raw account deletion that has not first scrubbed/transitioned its owned requests must fail the non-deleted-owner constraint atomically. No hidden cascade or automatic conversion in an FK trigger.

## 5. General-only enforcement and legacy cleanup contract

### 5.1 One capability owner

Add pure `S/domain/policy/discussion_product_policy.dart` with production General-only and supported coordination kinds `{plan}`. Retired persisted kind codes are **ask=2, blocker=3, promise=5**; plan is **1**. Keep these reserved constants and dormant repository logic. Never renumber enums.

Inject the policy at server composition. Only direct unit/repository tests may instantiate an internal multi-thread policy; do not add an environment variable, GraphQL argument, admin HTTP toggle, or client flag that enables it in a deployed server. Guard comments link both this plan and the architecture proposal and state that future multi-thread exposure requires a new authorization/API review.

### 5.2 Complete boundary inventory

| Surface | Required enforcement |
|---|---|
| Room list/create/target/seen | Gate explicit thread selection; General is null scope and the existing canonical General thread ID. `listThreads` returns exactly the General row for eligible users. |
| Message-ID actions | Load message, verify Beacon scope, then reject non-General before edit/delete/done/reaction/attachment/reply/target processing. No ID-only bypass. |
| Lifecycle write guard (**new — does not exist today**) | `BeaconRoomCase` currently contains **no** `BeaconStatus` check on any path: `_canUseRoom` tests author/steward/`roomAccess == admitted` only, and `createMessage` adds just block checks. §4.4's premise that "user message writes remain disabled" in closed/cancelled discussions is therefore false at this baseline and must be built, not assumed. Add an explicit lifecycle gate rejecting ordinary user writes (message create/edit/delete, reactions, attachments, replies, poll acts) when the Beacon status is closed, cancelled, or deleted, while leaving internal system-notice insertion unaffected. Negative tests per surface are required. |
| Replies and mentions | Reply target must share General scope and Beacon. Mention resolution retains existing target-admission rules. |
| Poll create/vote/read/options | Resolve the owning message for room polls and enforce its General + admission policy. Include `S/domain/use_case/polling_case.dart::create` and `mutation_polling.dart::pollingAct`, not just `BeaconRoomCase.createPoll`. Audit standalone poll behavior separately; do not accidentally disable unrelated supported polls. |
| Attachments/download/image resolution | Resolve owner message, enforce General and existing access before returning bytes or a signed URL. Blob IDs are not read capabilities. |
| Facts/plan provenance | Keep supported private/public fact policy; a room-source reference must be authorized and General. Do not expose a discarded conversation through fact/plan preview. |
| Coordination writes | Remove named retired fields from `MutationCoordinationItem.all`; generic update/remind/list/responsibility paths validate kind before persistence and expose only supported plan operations. |
| Notifications/paint/previews | No old thread destination or non-General snapshot emitted after cutover; no optional WS paint bypass. |
| Hasura and alternate writers | Do not track new private tables. Inspect nested selections/aggregates and existing room/poll relationships. Room-backed `polling`/`polling_variant` reads currently have broad filters; restrict room-backed rows through authorized General ownership while preserving existing standalone policy. |
| Deep links | Non-General legacy thread links show localized unavailable state, with an authorized Request overview fallback. Never reinterpret item IDs as child Beacon IDs. |

Retire these exact public mutation fields: `markBlocker`, `resolveBlocker`, `cancelBlocker`, `markAsk`, `createPromise`, `createDraftPromise`, `publishPromise`, `updateDraftPromise`, `deleteDraftPromise`, `acceptPromise`, `resolvePromise`, `cancelPromise`, `redirectPromise`, `createDraftAsk`, `publishAsk`, `updateDraftAsk`, `deleteDraftAsk`, `createDraftBlocker`, `publishBlocker`, `updateDraftBlocker`, `deleteDraftBlocker`, `acceptAsk`, `resolveAsk`, `cancelAsk`, `redirectAsk`.

Retain and audit: `updateCoordinationPlan`, `addPlanStep`, `resolvePlanStep`, `updateCoordinationItem` (plan-only), `remindCoordinationItem` (supported plan-only behavior), `markBeaconItemsSeen` (retained items only). Remove retired responsibility/reminder producers and client projections, not core help-offer admission/acknowledgement/exit flows.

### 5.3 Cleanup order

Task 00 produces an FK/producer manifest from both migrations and `pg_constraint` on the disposable fixture database. Task 09 implements that manifest; this is a required concrete artifact, not permission to guess foreign-key order.

1. Stop old writers/workers and enforce production capability before cleanup. Run migration under the deployment maintenance boundary, not while old app processes are accepting writes.
2. Snapshot exact doomed sets into transaction-local tables: retired kind IDs (2,3,5), all messages with `thread_item_id IS NOT NULL`, their attachments/polls/reactions/replies/seen rows, and derived task/attention references. Include mixed fixtures and no-op rerun evidence.
3. Preserve supported General messages, facts, plans, and steps. Null supported provenance into doomed messages/items where nullable. `beacon_fact_card.source_message_id` is nullable; preserve its existing fact text/visibility. Never manufacture a copied replacement message. For any non-null provenance constraint discovered, change only that provenance to nullable or prove the row itself belongs to the doomed set before deletion.
4. Remove/neutralize General system anchors and source-message footers referring to retired items. Prefer deletion of obsolete system anchor rows, keeping user messages. Clear only retired `linked_item_id`, event/footer JSON, linked message/parent references; retain valid plan/fact links.
5. Cancel/delete obsolete scheduled reminders, responsibility rows, attention channel jobs/receipts/occurrences and stale notification destinations in FK order. Preserve unrelated attention. Keep safe non-actionable historical representations only where existing retention requires them; no dangling link is considered safe.
6. Clear surviving reply/provenance references to doomed messages; delete dependent reactions, room-owned poll acts/options/polls, attachments and semantic messages. Remove obsolete per-thread seen rows; retain General seen timestamps. Delete retired item dependents and then retired items. Do not drop reusable thread columns/indexes/tables.
7. Queue unreferenced blobs through current GC ownership/refcount rules. Shared images used elsewhere survive. No object-store calls in SQL migration.
8. Rebuild only affected previews/unread/attention counts from remaining General data. Cleanup alone must not mark valid General history unread or mark new messages seen. Suppress misleading cleanup notification fan-out and issue one authorized catch-up after maintenance.
9. Assert no retired kind, non-General message, obsolete active job, broken FK, or actionable retired destination remains; assert retained fixture counts/values/General watermarks. Record before/after counts and backup identifier. The migration is irreversible; rollback is database restore plus matching application versions.

## 6. Client and realtime specification

### 6.1 Request surface

Use the existing request shell. Rename its user-facing “Threads” tab to **Discussion**; keep People and Log. Internal `features/beacon_threads` paths may remain to avoid a cross-feature rename. The Discussion overview contains General, then **Child requests** with **Create child request**, active list, finished list, and a collapsed deleted list. Keep supported Plans access as a separately named non-conversation section/action using existing plan UI; no plan thread is opened. Facts stay in their existing supported surface.

For a non-admitted viewer: do not fetch/show child lists or create controls; retain existing admission/request-detail UI. For an admitted terminal parent: lists remain readable, creation is unavailable with existing lifecycle wording. An admitted eligible parent with no children shows “No child requests yet” and the create action. Pagination is per group with explicit “Load more”; show a group error/retry without wiping other groups. No child chat preview, child unread badge, child participant count, review result, or recursive breadcrumb in v1.

Cards show permitted title, owner/avatar, existing request status presentation. Deleted cards say “Deleted request” and have no normal request-content destination. Tap normal cards using root-owned normal `BeaconViewRoute` navigation. The child's header offers an authorized immediate-parent link; inaccessible parent is a non-actionable “Parent request unavailable”. Do not push `ThreadDetailRoute` with child/item IDs.

General retains its current independent room message preview/unread watermark. Navigating parent → child or refreshing child cards must not invoke child `markSeen`. General room hosting always passes null thread scope; remove semantic thread selection state from the product host, while retaining internal server support.

### 6.2 Composer and message rendering

Pass typed creation context into `BeaconCreateScreen`/Cubit, not into arbitrary `Beacon.copyWith` parent fields. `BeaconHierarchyCase` supplies capability/source preview and delegates saving to the extended `BeaconCreateCase`. UI receives canonical saved draft state on errors. Source promotion is one message action “Create child request”; replace only retired Ask/Promise/Blocker targets and fields. Keep other valid actions such as reply, pin fact, and supported plan actions.

A shared new `C/features/beacon_threads/ui/widget/beacon_hierarchy_notice.dart` renders typed creation/lifecycle events using the participant-admission notice visual family. A separate source footer points to the promoted child. No faux source-author message or duplicate inline request card. Footer resolves deleted/unavailable child safely. Editing/deleting source messages updates footer/provenance without mutating the child. The live message action owner is `C/features/beacon_threads/ui/widget/beacon_room_body.dart::_onMessageActionsPressed` and `_openCoordinationComposerFromMessage`; update those call sites, not only `room_message_tile.dart` or the old fields sheet.

All new copy goes in every `packages/client/l10n/app_*.arb` locale. Prescribe keys `beaconChildRequestsTitle`, `beaconCreateChildRequest`, `beaconChildRequestsEmpty`, `beaconParentRequest`, `beaconParentUnavailable`, `beaconDeletedChild`, `beaconPromotionAlreadyExists`, `beaconLegacyThreadUnavailable`, plus typed hierarchy lifecycle templates. English product nouns are Request/discussion/General; Russian uses запрос/обсуждение/Общее, not the retired ask translation просьба for children.

Use `context.tt`, `TenturaText.*`, existing avatars/status text/action components, and themed Material 3 controls. No raw styling constants or pill status UI. Verify 360, 600, and 1024 logical widths, light/dark, text scale 1.0 and 2.0. Keep tap targets, long-title wrapping, loading/error rows, keyboard focus, and semantic labels usable. No golden update is accepted without viewing the result.

### 6.3 Realtime contract

Add wire kind `beacon_hierarchy`, aggregate ID = the projection owner's Beacon ID. The payload contains only the usual entity/id/event/actor fields; **no child IDs, titles, counts, private draft IDs, or paint**. Map it in `C/domain/entity/realtime/realtime_entity_change.dart` and the contract manifest.

| Change | Authorized hints / refresh |
|---|---|
| Child publication | Child ordinary Beacon invalidation; immediate parent's hierarchy projection to eligible parent participants including actor. |
| Child title/owner-safe summary/status/tombstone | Parent hierarchy projection plus ordinary child projections. Draft edits notify only owner through existing draft channels. |
| Admission/stewardship/block change | Changed request and adjacent hierarchy projections whose read path changes; include previously authorized affected account so it can evict. Hint uses an already-known projection owner ID, never a newly inaccessible child ID. |
| Parent delete / source link availability | Child's parent-reference projection and parent-list audience as authorized; lifecycle notices are separate outbox delivery effects. |
| Hierarchy notice materialization | Existing receiving-request `room_message` and attention invalidations, including actor sessions. |

Compute old/new authorization recipients under the mutation transaction; use bounded indexed fan-out helpers and existing byte/count limits. Do not broadcast child existence to all accounts or subscribe arbitrary client IDs. Extend `BeaconHierarchyCase` and appropriate request-view cases to map hints and catch-ups into page/parent-reference refresh. Add account/generation guards, one in-flight refresh plus one queued rerun, and preserve usable state on transient errors. An authoritative access denial clears cached parent/child data and controls immediately. Reconnect, restored browser visibility, and PG listener recovery refetch active hierarchy projections even if a notice/hint was missed.

## 7. Ordered work packets

Each packet is a coherent implementation/review unit, not necessarily a separately deployable release. Incomplete packets stay on the implementation branch. Do not deploy additive migrations that remove API access or change erasure constraints before their compatible code is ready.

### Task 00 — Inventory, journal, and fixture harness

Depends on: none. Changes: documentation and tests/harness only.

- Create the implementation journal and a machine-readable `docs/plans/nested-requests-boundary-inventory.json` with entries `{path,symbol,surface,scopeInput,decision,test}`. Inventory every public scope-bearing operation, every status writer/finalizer caller, admission/block writer, FK cleanup dependency, current reminder/responsibility producer, route, and notification destination.
- Start from the exact anchors in §§2/5; use symbol references and targeted searches. Enumerate `MutationCoordinationItem.all`, `MutationBeaconRoom`, `QueryBeaconRoom`, poll/fact/attachment handlers, Hasura metadata, room snapshot lookup and WS paint handling. Record actual generic query names rather than guessing them.
- Add new PG fixture helper `ST/support/beacon_hierarchy_fixture.dart`: unique DB, A/B/C/D topology, independent users/admission/forwards/offers, private drafts, retired/supported item/message fixtures. Fixtures inserted before enforcing production capability use a privileged test-only connection; public-contract actions use runtime authorization.
- Capture baseline focused tests, migration registration, schema fetch mechanism, and lint counts. Query FK definitions on this disposable DB and append dependency edges to the manifest. Inspect generated code only as evidence, never edit it.

Acceptance: manifest covers every surface in §5.2 and every producer in §4.3; existing `ST/architecture/transactional_attention_producer_inventory_test.dart` reviewed; no application behavior changed. Record exact PG command/environment without secrets. Additionally enumerate (a) every current `canReadContent` / `BeaconAccessGuard.canReadContent` caller with its downstream effect (read vs mutation), and (b) every `public."user"(id)` reference with its actual `pg_constraint` delete action and an assigned erasure disposition per §4.5. Both lists are required artifacts, not optional annexes.

### Task 01 — Pure contracts and policies

Depends on 00. Files: root values from §3.3; new server ports/cases' interfaces; `S/domain/policy/discussion_product_policy.dart`, new `beacon_hierarchy_policy.dart`; `S/domain/beacon_visibility.dart`; new client port.

- Implement immutable values, lifecycle eligibility/directions, one-edge visibility facts, supported-kind policy, errors. Preserve `canReadInvolvement` explicit role predicates.
- Specify interfaces before data adapters; use fake ports for focused policy tests. Do not inject SQL, `TenturaDb`, Ferry, `GetIt`, or GraphQL annotations into the new pure shared values/policies.

Acceptance: new `ST/domain/beacon_hierarchy_policy_test.dart` covers A/B/C/D, blocks/drafts/deleted states, all lifecycle transitions/no-ops/local reopen, reserved kind values. Extend existing `ST/domain/beacon_visibility_test.dart` and `beacon_lineage_visibility_test.dart` to prove hierarchy does not change lineage/involvement behavior.

### Task 02 — Additive hierarchy storage and repository adapter

Depends on 01. Files: `m0154`, table definitions, `tentura_db.dart`, new `S/data/repository/beacon_hierarchy_repository.dart`, `beacon_hierarchy_command_repository.dart`, `beacon_hierarchy_outbox_repository.dart`; Beacon row/domain mapping.

- Implement §4.1 tables/constraints/indexes, typed repository records, immutable parent/publication timestamp and event sequence. Do not expose hierarchy creation publicly yet.
- Implement keyset pages, private provenance, atomic command outcome records, set-based recursive target insertion, unique notices, and due-work selection. Keep transaction ownership at cases; adapters share current `TenturaDb`.
- Regenerate server code. Use `EXPLAIN` on a branching multi-level fixture to verify indexed immediate-parent reads and no per-node application query loop.

Acceptance: new `ST/data/repository/beacon_hierarchy_repository_pg_test.dart`, `beacon_hierarchy_command_pg_test.dart`, `beacon_hierarchy_outbox_pg_test.dart`: immutable parent update/attach/detach rejection, self/cycle/missing/draft-parent rejection, stable group pagination, unpublished exclusion, fork distinction, concurrent unique promotion, command hash conflicts, traversal through tombstones. Migration applies from previous schema and a clean database. Assert the delivery table carries `lease_owner`/`lease_until` and the five-state model, and that `beacon_room_message.author_id` is nullable with `ON DELETE SET NULL` plus the system-message discriminator and its ordinary-author constraint.

### Task 03 — Authorization, SQL/Hasura parity, and mutation locking

Depends on 02. Files: `m0155` (one-edge/linked-detail functions, effective-admission helper, lock helper/triggers); `beacon_access_repository.dart`; visibility facts; `hasura/metadata.json`; mutation owners identified in Task 00.

- Implement direct `beacon_effective_admission` SQL helper and current canonical content predicate with two one-edge EXISTS clauses. Keep involvement predicate's explicit involvement requirements; do not widen profile/Inbox/My Work queries.
- Implement capabilities/parent/source read projections; metadata exposes only intentional projections. Do not add unrestricted parent/children object relationships. Keep owner/media selection at ordinary content tier and protected surfaces on their own predicates.
- Apply §4.2 mutex before row locks in all named relevant command paths. Account erasure remains unenabled until Task 08. Verify nested UoW rollback/actor semantics rather than assuming them.

Acceptance: new `ST/data/repository/beacon_hierarchy_visibility_pg_test.dart`, `ST/api/beacon_hierarchy_hasura_parity_test.dart`, `ST/domain/use_case/beacon_hierarchy_case_test.dart`. Test raw IDs, nested selections/aggregates, owner/avatar/media reads, blocks in both directions, revoked grant with/without independent access, no transitive grants or discovery insertion. Use real user-session Hasura queries, not admin queries as authorization proof. Prove the one-edge grants live in `canReadLinkedDetail` only: for a hierarchy-only viewer, assert `canReadContent` is unchanged and that help-offer, forward, fork/lineage, invitation, and `helpOffersWithCoordination` all still refuse. A forward minted by a parent-only admittee must be impossible — this is the non-transitivity proof for non-negotiable outcome 2.

### Task 04 — Shared normal creation and atomic child commands

Depends on 03. Files: `BeaconCase`, new `BeaconCreationPolicy`, `BeaconChildCreateCase`, hierarchy command adapter; normal repository create/publish methods; exception mapping.

- Extract current normalization/rate-limit/media-independent creation validation without changing standalone behavior. The child case invokes the shared collaborator inside its transaction, never calls a GraphQL resolver or commits through a separate connection.
- Implement §3.4, including private drafts, publication delegation, source validation, idempotency, promotion uniqueness, parent General creation notice, and source footer read join.
- Revalidate source/parent under locks. Source delete nulls provenance and removes stale quote navigation. Input parentage is absent from normal updates and immutable in DB. Add no inherited roles/forward edges.

Acceptance: new `ST/domain/use_case/beacon_child_create_case_test.dart` and `ST/data/repository/beacon_child_create_atomic_pg_test.dart`. Inject failures after child insert/provenance/notice/attention and prove full rollback. Race two promotions, lost response retry, parent close/cancel/delete, admission removal, block insertion, source deletion, and draft publication. Wrapping up still allows publication. Existing standalone create/media/fork tests remain green.

### Task 05 — Lifecycle producers and retained status audience

Depends on 04. Files: `BeaconLifecycleEffectsCase`; `BeaconCase`, `EvaluationCase`, `ReviewFinalizationCase`, `AttentionExpirySweepCase`; notification context port/entity/adapter; `AttentionIntentCase`/attention policy; producer inventory test.

- Implement §4.3 at exact transition owners. Final Closed is produced once in the finalizer, not again by its early-close/expiry callers. Immediate close branch records its own event because it does not traverse review finalization.
- Replace retired-item recipient dependency with explicit retained role facts; preserve normal watcher-channel and actor/block behavior.
- Keep all review participants/evidence/trust effects scoped to the source Beacon. Record and test no-op/reopen/reclose identities.

Acceptance: new `ST/domain/use_case/beacon_lifecycle_effects_test.dart`, `ST/data/repository/beacon_hierarchy_lifecycle_atomic_pg_test.dart`, and `ST/domain/attention/beacon_status_audience_test.dart`. Extend existing evaluation/finalizer tests and `transactional_attention_producer_inventory_test.dart`. Inject outbox failure to prove source status and ordinary attention roll back together. Compare manual finalization and expiry event shapes.

### Task 06 — Durable hierarchy delivery worker

Depends on 05. Files: `BeaconHierarchyDeliveryCase`, outbox adapter, `TaskWorkerCase`, attention models/policy/destination/channel handling, room system notice persistence.

- Implement §4.4 transaction/claim/order/retry rules and destination-safe copy. Add a typed attention event, not a reused request-status payload with mismatched source fields.
- General-only user-message lifecycle guards must not prevent internal system insertion into retained closed/cancelled discussions. Deleted destination gets suppressed bookkeeping only.
- Ensure notification links target receiving General/message, with authorized source enrichment only during UI reads.

Acceptance: new `ST/domain/use_case/beacon_hierarchy_delivery_case_test.dart`, `ST/data/repository/beacon_hierarchy_delivery_pg_test.dart`. Cover failure before/after notice insert, dispatcher failure, crash after commit, duplicate workers, failed predecessor ordering, several source events, deleted intermediate/destination, current-audience snapshot timing, actor suppression, watcher preferences, recipient block/revocation, and no text/title leakage. Assert one occurrence/notice per event-target pair and correct queue metrics. Additionally prove claim fencing: an expired lease is re-claimable; a stale worker's owner-qualified failure update cannot overwrite a row another worker has `delivered`; and a row `parked` after the failure threshold unblocks strictly later events for that pair while remaining a durable undelivered record. Assert notices materialize with a null (system) author and no personal identity in the projection.

### Task 07 — Enforce General-only public product

Depends on 06. Files: `m0156` (General-only persistence protection, lifecycle write-guard support); scope-bearing handlers/cases from manifest; `mutation_coordination_item.dart`, `mutation_beacon_room.dart`, `query_beacon_room.dart`, `schema.dart`, `custom_types.dart`, `hasura/metadata.json`; production capability composition; dormant-test setup.

- Apply all §5.2 guards and remove listed retired schema fields. Keep surviving plan APIs and lower-level internal thread methods.
- **Retire the client documents in this task, not in Task 12.** Exactly 25 client documents under `C/features/coordination_item/data/gql/` still select the retired mutation fields (`coordination_item_mark_ask.graphql`, `coordination_item_create_promise.graphql`, …). `packages/client/build.yaml` points `ferry_generator|graphql_builder` at `tentura|lib/data/gql/schema.graphql`, so every document is validated against the fetched schema. Once Task 07 removes those fields from the server schema, Task 10's `schema_fetcher` + `build_runner` regeneration **fails** while these documents remain. Delete them and their generated imports/usages here, together with the server-side removal, so the schema and the documents never disagree across a task boundary. Task 12 then only removes the remaining UI surfaces.
- Gate ID-only operations before reads/mutations/bytes. Restrict room-backed Hasura polls and WS paint. Disable retired reminder/responsibility workers so cleanup cannot be undone.
- Add DB protection for unsupported runtime-role writes. Use the explicit test-only capability/role for dormant repository tests, never a runtime setting.

Acceptance: new `ST/api/general_only_public_contract_test.dart`, `ST/architecture/general_only_boundary_inventory_test.dart`; negative endpoint matrix contains every Task 00 entry. Existing `ST/domain/use_case/beacon_threads_case_test.dart`, `beacon_room_case_plan_thread_test.dart`, and `ST/data/repository/beacon_threads_repository_pg_test.dart` are split/reclassified where needed: production tests reject item scope; internal fixtures still prove dormant mechanics. Supported General replies/reactions/attachments/polls/mentions/plans/facts pass. Include negative lifecycle-guard tests: ordinary user message create/edit/delete, reactions, attachments, replies and poll acts are all rejected on closed/cancelled/deleted requests, while internal system-notice insertion into those same rooms still succeeds. Assert the 25 retired client documents are gone and client codegen succeeds against the reduced schema.

### Task 08 — Safe request deletion and account erasure

Depends on 07. Files: `m0157` (tombstone/erasure FKs, nullable room-message author), `beacons.dart`, structural mapper, `UserCase`, user/Beacon/image GC ports and repositories, deletion effects.

- Implement §4.5 nullable tombstone owner, published structural retention and erased-content cleanup. Ordinary deleted request links never expose the previous normal entity.
- Preserve nested structure and independently owned child behavior. Ensure request delete, source message delete, and account delete have distinct, tested effects.

Acceptance: new `ST/domain/use_case/beacon_hierarchy_erasure_pg_test.dart`; extend existing `ST/domain/use_case/user_delete_attention_pg_test.dart`. Delete owner of A or B in A→B→C with different owners: surviving child lifecycle/admission/media/evaluation unchanged, ancestor structure retained, personal content scrubbed, pending notices safe. Test failed erasure rollback and direct raw account deletion denial. No object-store deletion inside DB transaction. Prove every user-FK disposition from the Task 00 inventory: the `ON DELETE RESTRICT` fact pinner and each `NO ACTION` actor reference (admission, commitment, plan creator/target/acceptor, help-response author) is nulled or anonymised so erasure completes, with supported plans, facts and help state surviving. Prove erasing a notice author leaves delivered hierarchy notices intact and their delivery rows consistent.

### Task 09 — Scoped legacy cleanup migration

Depends on 08. Files: `m0158`; audited manifest; existing GC/reconciliation helper inputs if needed.

- Implement §5.3 using actual FK edges. Build a migration-upgrade fixture at pre-retirement schema, then apply cleanup. Do not implement the fixture by inserting doomed data through newly disabled public APIs.
- Record backup/restore procedure and before/after SQL assertions. No execution against shared/current user data during coding acceptance.

Acceptance: new `ST/data/database/nested_requests_cleanup_pg_test.dart`: mixed supported/retired records, private drafts, General references, non-General polls/attachments, shared blobs, queue/attention destinations, seen/previews. Assert no supported row/content/General watermark loss and no republishing private conversations. A database restore rehearsal is a deployment gate, not an application down-migration.

### Task 10 — V2 hierarchy schema and generated client transport

Depends on 09. Files: new `S/api/controllers/graphql/query/query_beacon_hierarchy.dart`, `mutation/mutation_beacon_hierarchy.dart`, their existing `query/_queries_all.dart` and `mutation/_mutations_all.dart` registries, `custom_types.dart`, `schema.dart`, input fields; client hierarchy `.graphql`/mapper/repository; `build_client.dart`; DI sources.

- Implement exact §3.5 operation names/shapes. Register each **client document name** in `_tenturaDirectOperationNames`. Do not rely on field-name registration.
- Start compatible local server, apply Hasura metadata/reload the Tentura remote schema, run the existing `schema_fetcher`, then regenerate server/client bindings. Align list nullability/input coercion with current GraphQL workarounds; read `packages/server/WORKAROUNDS.md` before changing those types.
- New client adapter returns pure values, with typed error translation and no unrestricted raw parent/child GraphQL relationship.

Acceptance: new `ST/api/beacon_hierarchy_graphql_contract_test.dart`, `CT/features/beacon/beacon_hierarchy_repository_test.dart`, `CT/data/service/beacon_hierarchy_direct_routing_test.dart`. Execute each operation over direct V2 with user auth; prove it reaches V2, maps results/errors, and rejects unauthorized IDs. Generated schema contains new fields and no retired public mutations. DI bootstraps dev/test correctly.

### Task 11 — Extend existing composer/save flow

Depends on 10. Files: `BeaconCreateCase`, `BeaconSaveCommand/Result/Failure`, `BeaconWritePort` as needed, `BeaconCreateCubit/State/Screen`, new `BeaconHierarchyCase`, promotion entry wiring.

- Implement child draft-first media flow and publication phase from §3.4. Persist command identity and canonical saved draft context through retries/restoration. Never infer creation success from a temporary/local key.
- Add editable authorized source preview; seed description only. Do not copy source attachments/mentions or expose private quotes in child payloads. Server capability failure yields actionable localized state and keeps draft/media available.
- Inject the coordinating case into Cubits; keep transport/DTO logic in adapters. Preserve current standalone create/edit/fork behavior.

Acceptance: new `CT/domain/use_case/beacon_child_save_test.dart`, `CT/features/beacon_create/beacon_child_create_cubit_test.dart`: lost creation response, changed form after unknown result, stage/reconcile/publish failure recovery, denied publication retaining draft, promotion conflict, restored draft, normal standalone regression. Assert exactly one canonical child and no premature publication.

### Task 12 — Child request surface, General host, and safe navigation

Depends on 11. Files: `threads_list.dart`, `threads_cubit.dart`, `threads_state.dart`, `thread_host_cubit.dart`, request view header/tab copy, new `beacon_hierarchy_cubit.dart`/state/widgets within `features/beacon_threads/ui/`, root router/deep-link files, l10n, test IDs.

- Implement §6.1 without recasting children as `RequestThread`/`CoordinationItem`. Let the hierarchy Cubit own hierarchy pages through `BeaconHierarchyCase`; keep General state separately owned by existing room/thread case.
- Remove retired creation controls, semantic-thread rows/routes, item unread badges, and retired responsibility rows. The retired client mutation documents/imports were already deleted in Task 07 (see that task); this task removes only the remaining UI surfaces that referenced them. Retain plan/step/fact access and core help/acknowledgement UI. Do not remove all coordination-item code indiscriminately.
- Root-owned navigation opens child Beacon views; legacy non-General links show unavailable/authorized overview. General and source-message links remain valid.

Acceptance: new `CT/features/beacon_threads/beacon_hierarchy_cubit_test.dart`, `beacon_hierarchy_view_test.dart`, `CT/app/router/nested_beacon_navigation_test.dart`. Cover admitted/non-admitted/terminal/empty/loading/error/pagination/tombstone, parent link states, local access eviction, General-only host, independent watermarks, surviving plan actions, old links and back navigation. Intentionally inspect widget/golden images at specified widths/scales/themes.

### Task 13 — Typed notices and promoted-source footer

Depends on 12. Files: typed room-message event mapping, new notice widget, `room_message_tile.dart`, source footer/promotion action, attention destination resolution and l10n.

- Render creation and lifecycle notices using admission-notice chrome and dated generic copy. Resolve source links only through guarded reads. Unknown event versions fall back to generic non-actionable system-event text.
- Preserve user message/reaction/date chrome. Source footer opens normal child request. Source edit/delete and inaccessible/deleted child are safe states; no parent-chat quote leaks into child content.

Acceptance: new `CT/features/beacon_threads/beacon_hierarchy_notice_test.dart`, `beacon_child_promotion_footer_test.dart`; extend notification navigation tests identified in Task 00. Assert semantic labels, actor chat visibility, no inaccessible source title/avatar/body, proper destination General/message selection and no child watermark changes from parent footer rendering.

### Task 14 — Realtime producers and convergence

Depends on 13. Files: hierarchy publisher SQL in its own new `m0159` (before release only; never appended to `m0155`), canonical contract, server recipient/snapshot adapters, client entity kind and owning cases/Cubits, integration driver.

- Implement §6.3 insert/update/delete/access-revocation recipients with bounded payloads, actor echo, and no draft leaks. Update manifest producer/impact/test entries together.
- Implement catch-up, guarded refresh, and cache eviction; scope generation by account and request. Child summary lifecycle invalidation must not wait for the delivery worker.
- Extend the existing multiclient test harness with a nested-request scenario; do not replace its existing acceptance scenarios or lower repeat/negative-proof settings for final evidence.

Acceptance: new `ST/data/repository/beacon_hierarchy_realtime_pg_test.dart`, `CT/features/beacon_threads/beacon_hierarchy_realtime_test.dart`; all existing contract tests named in the manifest. Two sessions prove create/status/title/promotion convergence, independent General unread, actor echo, revocation/blocks, reconnect and hidden-tab restoration. No child appears in Inbox/My Work without an actual ordinary involvement action.

### Task 15 — Whole-product regression and release documentation

Depends on 14. Files: acceptance tests, current-state product/visibility/API docs, terminology rules, `docs/README.md`, release version/gate/cache-buster sources.

- Exercise an actual child through normal forward → help offer → admission/acknowledgement → participation exit/review → finalization. Confirm no parent-side mutation/trust effect. Exercise parent close with child still active and independently closable.
- Update `CONTEXT.md`, `docs/features/beacon_room.md`, `docs/Tentura_current_status_quo.md`, `docs/beacon-visibility-matrix.md`, ADR 0008, API/coordination terminology and realtime docs to the implemented state. Explain nesting separately from ADR 0004 fork lineage. Archive/supersede old semantic-thread plans only after acceptance; preserve their historical evidence.
- Breaking release: set client `7.0.0` (or next valid major after rebase), update tracked `web/index.html` bootstrap query to match, set `kDefaultMinClientVersion` to that release, update `.env.example` override guidance, and audit active deployment overrides. Versioning the affected server package follows the same major rule when that package is released.
- Do not claim UI cache-buster changed through build_runner. Run a real web build or explicitly verify the tracked query matches. Do not stage skip-worktree `web/manifest.json`.

Acceptance: §8 complete, no unexplained failures, generated source inputs coherent, mixed-version stale mutation/queued-operation tests return explicit rejection/upgrade state. Journal records all gates and no unimplemented acceptance item. Only then is deployment preparation complete.

## 8. Verification commands and required evidence

Run focused tests named in each task from the package root. Tests marked PG must use a uniquely named disposable database, verify `SELECT current_database()`, apply migrations, and execute serially. Some existing PG tests create their own disposable databases; record those actual names too. Never use a green shared `postgres` run as acceptance.

Task 00 must establish the local credentials/host without printing secrets and record a reusable invocation. Existing helper `packages/server/bin/utils/run_migrations_once.dart` is the migration entry. At this baseline `Env._env` is `Platform.environment` and `pgDatabase` defaults from `POSTGRES_DBNAME`; the helper inherits that setting. Recheck this if the runner changes. Prove the connection's actual database, rather than relying only on environment configuration.

Representative invocation with the established local administrative environment (`POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USERNAME`, `POSTGRES_PASSWORD`) already loaded without logging secrets:

```bash
# In packages/server. Never reuse a shared database name.
export POSTGRES_DBNAME="tentura_nested_$(date -u +%Y%m%d%H%M%S)_$$"
PGPASSWORD="$POSTGRES_PASSWORD" createdb --host="$POSTGRES_HOST" --port="$POSTGRES_PORT" --username="$POSTGRES_USERNAME" "$POSTGRES_DBNAME"
PGPASSWORD="$POSTGRES_PASSWORD" psql --host="$POSTGRES_HOST" --port="$POSTGRES_PORT" --username="$POSTGRES_USERNAME" --dbname="$POSTGRES_DBNAME" --no-align --tuples-only --command='SELECT current_database()'
# Assert the printed value exactly equals POSTGRES_DBNAME before proceeding.
dart run bin/utils/run_migrations_once.dart
dart test -t pg -j 1
```

The implementation journal must include the exact database creation/current_database/migration/test commands used, success markers, no skipped relevant PG groups, and cleanup of that named database after retaining logs. Existing secrets may be used through the environment, never echoed into artifacts.

Required final checks (repository root unless the command uses a subshell):

```bash
(cd packages/server && dart run build_runner build -d)
# With matching running schema/metadata, after new server schema is available:
docker compose run --rm schema_fetcher
(cd packages/client && flutter gen-l10n && dart run build_runner build -d)
(cd packages/tentura_lints && dart test)
./scripts/check-custom-lints.sh packages/server
./scripts/check-custom-lints.sh packages/client
(cd packages/server && dart test --exclude-tags pg)
(cd packages/client && flutter test --dart-define=ENV=test)
bash scripts/check-user-facing-terminology.sh
git diff --check
```

Web artifact verification is a separate build gate. `verify_web_version_consistency.dart` inspects **build/web**, including the generated preload manifest and cache service worker; it cannot validate a source-only version edit. Use the matching environment's existing web-build configuration and the pipeline's build/post-processing order:

```bash
# In packages/client, with the approved local/staging build environment available:
flutter build web --profile --wasm --pwa-strategy=none --source-maps --base-href=/ --dart-define-from-file=../../.env
dart tool/apply_google_maps_web_key.dart
dart run tool/trim_web_deploy_artifact.dart
dart run tool/apply_versioned_web_assets.dart
dart run tool/generate_wasm_preload_artifacts.dart
dart run tool/verify_web_version_consistency.dart
```

Supply any deployment-specific SERVER_NAME/IMAGE_SERVER/Sentry/build identity defines using the existing pipeline configuration; do not invent production values or overwrite `.env`. Record those non-secret build arguments in the journal. Also compare the tracked source `web/index.html` bootstrap version with `pubspec.yaml`, since generated artifact success alone does not prove the source cache-buster was committed.

Run the serial PG suite separately with the proved disposable environment. The current root project may also gain shared-value tests in Task 01; if so, run `dart test` at root and list its files in the journal. Do not use Flutter analyze, subdirectory Dart analyze, or Dart MCP analyze as a substitute for package-root custom-lint gates. Regenerate goldens only intentionally and inspect their images.

Browser acceptance uses `./scripts/run_realtime_multiclient_web_local.sh` after extending its existing driver with hierarchy scenarios. It owns API port 2080, Flutter port 8888 and independent browser sessions; inspect occupied ports first. Preserve default five consecutive runs and negative-proof checks for final acceptance. Record runner terminal completion, log/artifact directory, exact version/commit, and the new scenario's assertions. A manually successful API walkthrough or a shared dev-server screenshot does not substitute for this gate.

### Minimum end-to-end scenario

1. Alice owns A; Bob is admitted. Bob publishes B from Alice's General message, then creates C under B; Alice sees B card without Inbox/My Work/child General access. Bob's child ownership does not depend on parent ownership.
2. Alice receives a normal forward for B: ordinary Inbox involvement appears. Alice accepts/obtains normal child admission: child General becomes available independently.
3. Close A: B and C get ancestor notices, keep their statuses and memberships, and have unchanged evaluation/trust state. A→B→C notices contain no private ancestor content for a C-only participant.
4. Close B: A and C receive notices; sibling D gets none. ReviewOpen and final Closed are separate, ordered, exactly-once events, including automatic expiry.
5. Delete A or erase its owner: B/C remain independent; structural navigation is a tombstone; pending descendant delivery still works. No user-facing path opens erased content.
6. Revoke a parent admission/block a relevant owner while another session has the hierarchy open: unauthorized cards/details are evicted, independently authorized child access survives, and reconnect converges.
7. Verify General replies/mentions/polls/facts/plans/help/acknowledgement/evaluation still work, and every retired public API/old deep link is unavailable.

## 9. Deployment and rollback boundary

This is one coordinated breaking activation, not a rolling mixed-server schema migration. Additive work may be tested earlier on disposable/staging databases, but no production activation occurs before all tasks pass.

1. Build matching server/client assets and capture verified schema/metadata/version artifacts. Prepare a database backup and prove restore to an isolated database. Record data-loss scope of `m0158` explicitly.
2. Enter maintenance; stop old server and worker processes and drain/disable queued old product writes. Prevent old runtime credentials from writing while migrations run. A minimum-client gate alone is insufficient.
3. Apply additive/visibility/tombstone/capability migrations with matching code, then the reviewed cleanup migration; verify SQL postconditions. Apply matching Hasura metadata and reload its remote schema against the new server before client schema smoke tests.
4. Start matching workers/server, ship matching client assets and `7.0.0` bootstrap/minimum gate, verify stale clients cannot exercise retired mutations, then leave maintenance.
5. Run hierarchy/direct-V2/Hasura authorization and worker-lag smoke checks; retain observed queue/notice/role evidence. Do not turn off General-only rejection as a rollback workaround.

Before cleanup, rollback can restore the matching pre-activation application/metadata if no incompatible writes were accepted. After cleanup, application-only rollback cannot recreate discarded messages/items. Restore the backup and matching old code/metadata/client assets as one maintenance operation, accepting loss of post-backup writes, or fix forward. Never run a down migration that silently detaches or deletes live children.

## 10. Completion definition

Implementation is complete only when all Task 00 inventory entries have code/test evidence, every acceptance property in the architecture proposal maps to a passing task gate, full PostgreSQL and multiclient proof is recorded, and current-state documentation/version/schema inputs agree. A passing policy test alone is not authorization, concurrency, or delivery proof. A blocked infrastructure/manual gate remains visibly pending in the journal; it is not converted to “done”.

This plan's preparation changed documentation only. No schema migration, cleanup, code generation, application version, running service, or product behavior was changed.

## 11. Change log

### Revision 2 — adversarial review (Reviewer: gpt-5.6-sol-xhigh, Critic: Claude Opus 5)

Ten findings survived a two-round reviewer/critic loop with evidence-typed disagreement. Each was verified against the live code before being applied.

| # | Sev | Finding | Resolution |
|---|---|---|---|
| 1 | CRITICAL | One-edge hierarchy grants added to canonical `canReadContent` would confer mutation authority, since that predicate is the sole gate in `help_offer_case`, `forward_case`, `beacon_lineage_visibility`, `invitation_case`, `coordination_case`. Forwarding is itself a content-read grant, so a parent-only admittee could mint child access for third parties — violating non-negotiable outcome 2. | §3.2: split out a narrower `canReadLinkedDetail` predicate; `canReadContent` semantics unchanged; consumer table + required Task 00/03 proofs added. |
| 2 | MAJOR | `beacon_hierarchy_deliveries` had no lease/fence, while §4.4 records failure scheduling in a separate transaction after the row lock is released — a stale worker can overwrite another worker's terminal state. | §4.1/§4.4: added `leased` state with `lease_owner`/`lease_until`, owner-qualified terminal updates, expired-lease crash recovery, modelled on `attention_channel_delivery_repository`. Consequence scoped to terminal-state corruption (the existing unique keys do prevent duplicate user-visible effects). |
| 3 | MAJOR | Lifecycle notices had no viable author: `beacon_room_message.author_id` is `NOT NULL`, automatic expiry has a null actor, and a real actor leaks identity through the message projection. | §4.4 step 2: `author_id` forward-migrated to nullable + system-message discriminator; projection renders null as generic system identity. |
| 4 | MAJOR | Task 07 removes retired schema fields, Task 10 regenerates the client from that schema, but the 25 client documents referencing them were not deleted until Task 12 — Ferry generation fails in between. | Client document retirement moved into Task 07 alongside the server-side removal; Task 12 de-duplicated. |
| 5 | MAJOR | Account erasure undefined for retained user FKs: `beacon_fact_card` pinner is `ON DELETE RESTRICT` and admission/commitment/plan/help-response actors default to `NO ACTION` — all block deletion. | §4.5: per-reference disposition table + mandatory Task 00 `pg_constraint` inventory with one of three assigned decisions each. |
| 6 | MAJOR | `m0155`/`m0156` were written in one task and amended in later tasks; `migrant` gates on the highest recorded `schema_version`, so appended SQL silently never runs. | §4.1: migrations declared immutable once applied and re-split to `m0155`–`m0159`, one owning task each (03/07/08/09/14); Task 03, 07, 08, 09 and 14 file lists updated to match. |
| 7 | MINOR | Plan named `beaconPublishDraft`; the real GraphQL field is `beaconPublish` / document `BeaconPublish` (`publishDraft` is only the domain method). | §3.4.8 and §3.5 corrected, with the two names explicitly distinguished. |
| 8 | MAJOR | Plan assumed closed/cancelled rooms already reject user writes; `BeaconRoomCase` contains no `BeaconStatus` check on any path. | §5.2: new explicit lifecycle write guard row, flagged as new work with required negative tests. |
| 9 | MAJOR | `beacon_room_message.author_id` is `ON DELETE CASCADE`, so erasing a notice author would delete already-delivered notices while delivery rows still read `delivered`. | Folded into the §4.4 step 2 authorship fix (`ON DELETE SET NULL`) with an erasure-integrity test. |
| 10 | MAJOR | A permanently failing delivery wedges all later notices for its (source, target) pair forever; "alert after 10 failures" named no remediation. | §4.4: audited operator `parked` terminal state, distinct from `suppressed`, unblocking strictly later events while recording the undelivered notice. |

Rejected during the loop: a claim that §4.1 never allocates the per-source hierarchy event sequence column — Task 02 (§7) does scope "event sequence" to `m0154`; only the summary row omits the column name. A suspected §5.2/§3.4.9 contradiction over General thread scope was also dropped: `'general'` is an API-layer alias normalised to `NULL` at persistence (`BeaconRoomCase` line ~748), so both statements are consistent.

Not re-litigated: the plan's claims about existing symbols, paths, migration numbers, versions, FK actions, kind codes and named test files were spot-checked extensively and were accurate.

### Revision 2a — findings propagated into the work packets

Revision 2 fixed the contracts in §§3–5 but left the §7 acceptance gates unchanged, so several new requirements had no verifying task gate (§10 requires every acceptance property to map to one). Propagated:

- **Task 00** — must now also inventory every `canReadContent` caller with its downstream effect, and every `public."user"(id)` reference with its real `pg_constraint` action and assigned erasure disposition.
- **Task 02** — asserts the delivery lease columns/five-state model and the nullable system-authored room message.
- **Task 03** — must prove the one-edge grants live only in `canReadLinkedDetail`: help-offer, forward, fork/lineage, invitation and `helpOffersWithCoordination` all still refuse a hierarchy-only viewer. Includes the explicit non-transitivity proof for non-negotiable outcome 2.
- **Task 06** — adds lease-fencing, stale-worker, and `parked` unblocking assertions plus system-author projection checks.
- **Task 07** — adds negative lifecycle-guard tests per surface, and asserts the 25 retired client documents are gone and codegen succeeds.
- **Task 08** — must prove each user-FK disposition and that erasing a notice author leaves delivered notices intact.
- **Migrations** — re-split to `m0155`–`m0159` with exactly one owning task each (03/07/08/09/14), so none is amended post-application; Task 03/07/08/09/14 file lists and the §9 data-loss reference updated accordingly.

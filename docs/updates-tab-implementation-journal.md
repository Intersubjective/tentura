# Updates Tab — Implementation Journal

This is the execution ledger for `docs/updates-tab-implementation-plan.md` (revision 4).
It is the context-reset source used before each plan task: read the named task, this
journal's current task entry, and the live worktree; do not rely on prior task detail
unless this journal identifies it as a prerequisite.

## Context reset — T-11

**Resolution:** added the default-off fifth Home branch in the required order, with
Updates at index 2 and Network/Profile shifting only when the compile-time flag is
enabled. `openFromUpdate` resolves the typed attention destination table and directs
Update-origin navigation into the mounted Updates branch without changing legacy
notification behavior. Directed Chat uses `message` separately from coordination
`item`; `BeaconViewScreen` passes it to `RoomCubit`, which requests the bounded,
server-authorized `roomMessageTarget` when the target is outside the initial page and
then uses the existing scroll path.

**Verification:** `dart run build_runner build -d`; focused router, destination-map,
Home-tab, and notification deep-link tests pass with Updates both disabled and enabled;
scoped analyzer has no errors; formatting and `git diff --check` pass.

## Context reset — T-15

**Resolution:** Updates is now the unconditional third Home branch and fifth visible
tab. The client flag and server new-producer gate are removed, so all T-05 producers
record attention receipts transactionally. The legacy client bell, route, feature, and
New Stuff notification-count plumbing are retired; `/notifications` redirects to
Updates. The server-side legacy Notification Center API remains for old-client
compatibility through T-19. Inbox/My Work local Drift dots and row highlights remain
explicitly out of this migration until T-21.

**Verification:** custom-lint tests, focused server/client suites, full client
analysis, terminology check, shell syntax, and `git diff --check` pass. The final
unconditional release proof is recorded below.

## Context reset — T-16

**Task packet:** add the separately named Needs you projection without changing the
Updates navigation badge, which remains the unread receipt count. Settlement and read
acknowledgement are independent facts: only newly materialized, recipient-specific
obligations participate; legacy rows stay non-obligations rather than being fabricated
as resolved.

**Resolution:** `m0118` adds `requires_action`, a typed/versioned
`attention_thread_key`, and independent settlement facts with database checks and
live-obligation indexes. The attention policy computes the recipient-specific
obligation projection at write time; the server feed has a third `needsYou` view/count
alongside the unchanged unread summary. The client exposes the distinct Needs you tab
and only offers Mark done for a live obligation.

**Unexpected findings:** server build generation repeats the repository's known
`drift_dev` circular-deserialization warning for the users/images tables. It still exits
zero and regenerated the required Freezed output.

**Verification:** the disposable PostgreSQL migration suite proves the typed-thread
constraint, legacy non-obligations, authorized/idempotent settlement, mandatory
non-dismissal, independent `seen_at`, and the Needs you projection/count. Focused
server GraphQL/policy tests and client attention/Updates tests pass; full server
analysis, scoped client analysis, terminology check, formatting, and `git diff --check`
pass. T-16 is complete.

## Context reset — T-17

**Resolution:** `TenturaChangeHighlight` centralizes the reduced-motion-aware,
accessible field emphasis used by the existing Beacon People/Items focus path. The new
`SeenAckCase` is pure: it accepts only viewport fraction, dwell duration, app focus, and
route-current evidence. `AttentionVisibilityAck` is the Flutter adapter around Updates
cards, using the existing `visibility_detector` dependency to acknowledge a receipt only
after 60% visibility for 800 ms on the focused current route.

**Unexpected finding:** `visibility_detector` was already declared by the client, so no
new rendering dependency or browser-specific domain API was needed.

**Verification:** focused domain attention/Updates tests and scoped Flutter analysis
pass, including the dwell boundary, unfocused app, and non-current route negatives.

## Context reset — T-12

**Resolution:** Updates cards now acknowledge before opening their typed destination,
offer an accessible per-card Mark seen action, and expose Mark all seen in the top bar.
The presenter delegates to the shared `AttentionCase`; it owns optimistic state and
failure reconciliation. The authoritative receipt cache is kept separate from projected
optimistic rows, so a rejected acknowledgement restores unread state instead of being
mistaken for server confirmation.

**Verification:** generated EN/RU l10n; focused acknowledgement and Updates tests pass,
including mark-all rollback and a simulated second client converging from the
account-scoped notification hint used by the Room bridge; flag-on router suite and
scoped analyzer pass; formatting and `git diff --check` pass.

## Context reset — T-13

**Resolution:** projected `mutedInAppEventClasses` through the existing notification
settings entity, V2 GraphQL repository, and cubit. Notification Settings now has an
In-app section for the two contract-owned noisy classes only: coordination churn and
Request progress. Mandatory/safety and obligation receipts are explained as always
visible rather than represented by misleading disabled toggles.

**Verification:** generated EN/RU l10n; settings cubit tests cover optimistic
persistence, rollback, and the constrained in-app registry; scoped analyzer and
`git diff --check` pass.

## Scope and task ledger

| Task | Status | Evidence / blocker |
| --- | --- | --- |
| T-00 | Complete | Live issue #80 checked line-by-line; ADR/contract/cross-package tests pass; all declared `inviteAccepted` live commands are characterized. |
| T-01 | Complete | m0115 is expand-only; PostgreSQL migration/rollback, legacy collapse, mapping, and notification regressions pass. |
| T-01b | Complete | m0116 atomically cuts over publishers; 500-row backfill and 1/50/500 update budgets pass on PostgreSQL. |
| T-02 | Complete | Narrow ports, recipient policy/full reason sets, m0117 authorized relation, atomic feed query, monotonic dual-write ack, and directed-room bridge pass unit and PostgreSQL proof. |
| T-03 | Complete | Reentrant actor-scoped UoW, transactional receipt writer, post-commit channel split, symmetric rollback, txid/GUC, collapse, and legacy-channel proofs pass. |
| T-04 | Complete | Every existing producer is cut over to transactional receipt recording; inventory, projection, destructive-ordering, PostgreSQL, and compatibility suites pass. |
| T-05 | Complete | Gated directed Chat, exhaustive Request-status, actor-null expiry, and reciprocal-connection producers pass unit, PostgreSQL, contract, and analyzer evidence. |
| T-06 | Complete | V2 attention feed/ack/preference/exact-target GraphQL plus direct routing and compatibility adapters pass focused verification. |
| T-07 | Complete | Deterministic shadow/budget proof plus the five-run enabled-QA soak show zero unexplained mismatches in `reports/realtime-multiclient/updates-t15-release-20260717`. |
| T-08 | Complete | Shared application slice, lazy default-off gate, V2 adapter, contract impacts, and focused refresh/account/ack/boundary tests pass. |
| T-09 | Complete | `HomeTabSpec` now owns the four existing tab mappings; focused router/Home/New Stuff tests and scoped analysis pass. |
| T-10 | Complete | Flagged, route-free Updates presenter with feed views, pagination, refresh, scroll retention, and EN/RU copy; focused verification passes. |
| T-11 | Complete | Flagged fifth branch, typed destination map, Updates-origin branch selection, and exact directed-Chat target hydration pass focused flag-off and flag-on router tests. |
| T-12 | Complete | Open/per-item/mark-all acknowledgement UI, optimistic rollback, and multi-client Room-bridge hint reconciliation pass focused verification. |
| T-13 | Complete | In-app noisy-class settings UI, V2 persistence mapping, safety copy, and focused cubit verification pass. |
| T-14 | Complete | Five browser release-proof passes, deliberate live/catch-up negative controls, and zero unexplained shadow mismatches are recorded in `reports/realtime-multiclient/updates-t14-release-20260717-005719`. |
| T-15 | Complete | Unconditional flip, scoped retry-proof hardening, five positive browser runs, and both deliberate negative controls pass in `reports/realtime-multiclient/updates-t15-release-20260717`. |
| T-16 | Complete | `m0118` settlement axis, distinct Needs you projection, Mark done flow, GraphQL/authorization boundary, and PostgreSQL migration/settlement proof pass without changing unread semantics. |
| T-17 | Complete | Tokenized changed-field highlight plus pure dwell policy and `visibility_detector` Updates-card adapter pass focused analysis/tests. |
| T-18 | Complete | Authorized payload-only indexed search with bounded GraphQL input, stable cursor paging, debounced Updates UI, and PostgreSQL EXPLAIN proof. |
| T-19 | Complete | Version-gated contract migration removes legacy Notification Center fields and active `read_at` writes; seen-only index and acknowledgement proof pass. |
| T-20–T-22 | Deferred | Explicitly out of v1 scope; require separate approval. |

## Worktree baseline — 2026-07-16

- The tree was already dirty before this execution. Relevant apparent Updates work is
  uncommitted: `docs/adr/0010-attention-receipt-extension.md`,
  `docs/contracts/updates-event-contract.json`, both architecture tests, `m0115`,
  notification-outbox/preference entities and repositories, and the PostgreSQL
  migration test. Treat all of it as existing work pending verification, not as
  completed implementation.
- Unrelated modified and untracked files exist throughout the repository (agent/rule
  files, other plans, reports, and unrelated server tests). Do not revert, stage, or
  attribute them to this plan.
- `git diff --check` passed at the baseline.

## Context reset — T-00

**Task packet:** validate the ADR, compact contract, and cross-package contract tests
against the eight issue-required classes and the revision-4 decisions. T-00 changes no
runtime product behavior, schema, producer, retention policy, or UI.

**Acceptance evidence required:** ADR records D-1 through D-8 and the specified
architectural choices/deferrals; compact JSON has exactly the five required facts for
each normative event type and marks only the three specified new producers as pending;
server and client architecture tests consume it and pass.

**Unexpected findings:** none recorded yet.

**Finding (requires T-00 fix):** the non-pending `inviteAccepted` contract row names
five live producer paths, but its pointed test currently proves only one of them. The
ADR requires every non-pending row's test to exercise its declared live
notification-port pathway. Add focused producer-characterization coverage or keep
T-00 in progress; do not weaken the contract declaration.

**Resolution:** added focused assertions to the existing command tests for
`AuthCase.signUp`, `AuthCase.signUpWithInvite`,
`CredentialAuthCase.resolveOrCreate`, `InvitationCase.accept`, and
`InvitationCase.acceptAsExisting`. All assert the legacy invite-accepted port receives
the expected inviter/accepter identity. The compact contract retains its single primary
test pointer as designed; the full server test suite now supplies the multi-command
characterization.

**Verification:** GitHub issue #80 fetched live; server/client Updates-contract tests,
the three invite producer test files, `tentura_lints` tests, terminology check, and
`git diff --check` passed. `dart analyze --no-fatal-warnings` (server) and
`flutter analyze --no-fatal-warnings --no-fatal-infos` (client) exited zero but emit
pre-existing diagnostics outside this task. Dart's analyzer does not accept
`--no-fatal-infos`; use the server form above.

## Context reset — T-01

**Task packet:** independently audit and, if needed, finish only the m0115 expand-only
schema extension and corresponding server entities/repository mappings. Do not begin
m0116, change realtime triggers, backfill, ports, GraphQL, producers, UI, or retention.

**Acceptance evidence required:** m0115 contains only C1 columns/constraints/indexes
and the in-app preference column; no backfill, trigger edit, index drop, or destructive
statement; forward migration/rollback behavior and legacy `read_at` collapse SQL remain
proven against PostgreSQL; entity/repository mapping preserves existing channel behavior.

**Prerequisite evidence:** T-00 complete as recorded above.

**Unexpected findings:**

- A disposable database cannot validate the historical SQL function bodies because
  the MeritRank `mr_*` functions are provisioned outside the Dart migration history.
  The pg harness now sets `check_function_bodies = false` while reconstructing the
  checked-in legacy schema; none of those external functions are executed by this
  suite.
- PostgreSQL package v3 rejects the rollback helper's original multi-command prepared
  statement. The helper now executes each reverse operation separately, which also
  makes rollback failures attributable to one statement.
- The real repository round-trip exposed an existing raw-`customSelect` timestamp
  bug: PostgreSQL returns `timestamptz` as text/`PgDateTime`, while
  `row.read<DateTime>` uses Drift's integer mapping. Outbox and preference repository
  boundaries now decode `DateTime`, `PgDateTime`, or text explicitly; the pg test also
  proves `seenAt`, `createdAt`, and `snoozeUntil` round-trips.

**Resolution:** independently audited the existing T-01 work, retained the exact C1
schema, hardened its disposable-database harness and teardown, and corrected the
timestamp mappings needed for real PostgreSQL repository reads. No m0116 trigger,
backfill, API, producer, or UI work was included.

**Verification:** the pg-tagged realtime/m0115 suite passes all 14 cases on a freshly
created disposable database; server/client compact-contract tests pass; 40 focused
notification service, email, legacy Notification Center, and preference tests pass;
server analysis exits zero with the repository's existing warning/info baseline; Dart
format and `git diff --check` pass.

## Context reset — T-01b

**Task packet:** add m0116 only: atomically replace the m0114 notification-outbox row
trigger with account-scoped statement-level INSERT/UPDATE/DELETE publishers, then
backfill `seen_at = read_at` under the new publisher. Do not add attention ports,
authorization, GraphQL, producers, client code, or retention changes.

**Acceptance evidence required:** one migration transaction cannot expose both row and
statement publishers; INSERT/UPDATE/DELETE emit one account-scoped `notification`
hint per touched account; UPDATE emits only for user-visible/read-state/collapse
changes; 1/50/500-row acknowledgement writes emit one frame per account; channel-only
changes are silent; backfill preserves unread compatibility without a row storm; a
server rollback to m0115 remains functional.

**Prerequisite evidence:** T-01 complete as recorded above.

**Unexpected findings:** the realtime machine contract still classified
`notification` as a generic `notify_entity_change('notification')` producer owned by
m0114. m0116 changes that implementation fact, so the contract and server architecture
test now classify its three operation-specific functions as specialized publishers and
search both m0114 and m0116. Wire kind, accepted aliases, client kind, and impacts are
unchanged.

**Resolution:** added m0116 with operation-specific transition-table functions and
three statement triggers. UPDATE compares read/seen/collapse plus every feed-visible
column, not `emailed_at`, `digested_at`, or `dedup_key`; account moves notify both old
and new account ids. The row trigger is dropped before the statement triggers are
created, and `seen_at = read_at` runs last. The Migrant PostgreSQL gateway executes all
statements for one `Migration` inside a single `runTx`, so no intermediate publisher
state commits. The rollback fixture restores the m0114 row trigger before reversing
m0115, while the legacy repository regression proves an old-server write remains valid
against the post-m0116 schema.

**Verification:** the disposable PostgreSQL suite passes all 16 cases, including a
500-row compatibility backfill with one aggregate hint, INSERT/UPDATE/DELETE over two
accounts, silent channel bookkeeping, and exact one-hint results for 1/50/500-row ack
updates. Server/client realtime and Updates contract tests pass; 42 notification,
email, legacy center, preference, and architecture tests pass; scoped analysis exits
zero with info-only pre-existing migration/test diagnostics; formatting and
`git diff --check` pass.

## Context reset — T-02

**Task packet:** introduce the narrow domain ports and entities for dispatch/query/ack
and unit-of-work, implement recipient-specific `AttentionPolicy.project`, refactor the
recipient resolver to retain full reason sets, and add the single SQL authorized
relation/query path from C3-C5. Do not migrate producers, expose GraphQL, or add client
code yet.

**Acceptance evidence required:** policy is table-driven against the compact event
contract; `visible_attention_receipts` is the only feed/badge/mark-all authorization
and in-app-mute predicate; summary plus page share one statement/snapshot with stable
composite pagination; `markSeen`, `markAllSeen`, and the Room watermark bridge are
monotonic and dual-write `read_at`; PostgreSQL tests cover every access policy,
recipient-safe allowlist, muted noisy rows, pagination, ack idempotency, and the
unread-summary/non-empty-page invariant; existing SQL/Dart visibility parity is
extended rather than duplicated.

**Prerequisite evidence:** T-01b complete as recorded above.

**Unexpected findings:**

- C4 described the legacy policy as content-only, but the live
  `filterBeaconNotifications` path also retains readable deleted-Request tombstones and
  replaces their title/body with generic copy. m0117 preserves that deployed behavior:
  the `legacy` branch delegates to content *or* tombstone SQL, and the query adapter
  sanitizes tombstone rows. Removing it would have been a privacy/compatibility
  regression, not a simplification.
- `BeaconRoomRepository.markBeaconRoomSeen` protected only main-room timestamps in the
  use case; its SQL upsert itself could regress either main or thread watermarks when
  called directly or raced. Both conflict clauses now persist `GREATEST(existing,
  incoming)`, and m0117 bridges only an inserted/advanced persisted watermark.
- Raw `jsonb` from the attention query is returned by Drift/PostgreSQL as a native Dart
  map in this statement shape rather than textual JSON. The attention mapper accepts
  either representation, matching T-01's explicit timestamp-boundary hardening.
- The existing migration reconstruction fixture must remove m0117 before rolling back
  m0116/m0115 because the new function correctly depends on the expanded receipt
  columns. Its rollback order now mirrors the production migration order.

**Resolution:** introduced domain-owned `AttentionDispatchPort`,
`AttentionQueryPort`, `AttentionAckPort`, and `MutatingUnitOfWorkPort` plus the outer
database UoW adapter. `AttentionPolicy.project` is recipient-specific and contract
driven; mandatory/standard max-wins over noisy reasons. The legacy recipient resolver
now accumulates every distinct reason per user while retaining the highest priority.
m0117 installs `visible_attention_receipts(account_id)` as the sole SQL authorization
and in-app-mute predicate, delegating Request decisions to ADR-0008 functions and
strictly allowlisting profile/recipient-safe terminal rows. `attentionFeed` derives
summary and stable `(created_at DESC, id DESC)` page rows from one materialized relation
in one statement. Ack operations are authorized, monotonic, idempotent, dual-write
`seen_at`/`read_at`, and the room bridge checks account, Request, thread, latest
collapsed message id, and message timestamp.

**Verification:** the policy/full-reason/service group passes 33 tests; the disposable
PostgreSQL attention suite passes all 4 cases (all five access policies, preference
suppression, tombstone sanitization, equal-timestamp cursor pagination, acknowledgement
idempotency, main/thread room bridge, and unread-summary invariant); the m0114-m0117
migration suite passes all 16 cases. The existing SQL/Dart visibility suite remains
green and now contains a relation-parity case (skipped only when the developer database
has not yet applied m0117). Scoped analysis reports no issues; `git diff --check`
passes.

## Context reset — T-03

**Task packet:** move transaction ownership into producing use cases through
`MutatingUnitOfWorkPort`, make affected repository commands transaction-neutral or
explicitly in-transaction, and split notification dispatch into in-transaction receipt
materialization plus strictly post-commit channel hand-off. Keep every live producer on
the legacy path in this deployable task; synthetic/pilot fixtures alone exercise the
new path. Do not migrate producer call sites or add GraphQL/client behavior yet.

**Acceptance evidence required:** domain code imports no `TenturaDb`; one PostgreSQL
transaction and actor GUC span synthetic domain and receipt writes; domain or receipt
failure rolls both back; channel hand-off cannot run before commit and channel failure
cannot affect committed domain/receipt rows; duplicate in-action receipt writes retain
collapse behavior; current push preference, quiet-hour/snooze, batching, email, digest,
and legacy producer behavior remain green.

**Prerequisite evidence:** T-02 complete as recorded above.

**Unexpected findings:** the repositories do not need dozens of parallel
`...InTransaction` methods. Drift transactions are zone-scoped, so the database adapter
can make the contract explicit once: an outer mutating transaction installs a private
database/actor context; nested `withMutatingUser` calls join only when both database and
actor match, and a mismatch throws. The PostgreSQL probe verifies one `txid_current()`
and actor GUC across a nested repository-shaped call and the receipt trigger, so this is
proved behavior rather than an assumption about arbitrary nesting. Actor-null work uses
an explicit system transaction context.

**Resolution:** added `AttentionDispatchRepository` as the
`AttentionDispatchPort` adapter. It applies the T-02 policy, writes/collapses the full
receipt shape without catch-and-continue behavior, and returns channel decisions.
`TransactionalAttentionCase` runs the domain mutation then receipt recording inside the
UoW and invokes the existing notification channel boundary only after commit; channel
errors are logged and cannot turn a committed domain action into a retryable failure.
`BeaconNotificationService` now exposes that post-commit hand-off and its legacy
`dispatch` compatibility path uses the same channel implementation after its legacy
outbox write. Push preferences, quiet hours/snooze, per-Request mute, lock-screen copy,
batch/direct FCM, immediate email, and digest semantics remain unchanged.

**Verification:** the disposable PostgreSQL attention suite now passes 7 cases,
including direct txid/GUC equality, nested actor join, domain-failure rollback,
foreign-key receipt-failure rollback, post-commit visibility, channel-failure
isolation, and duplicate collapse. Scoped analysis reports no issues; domain has no
data/database imports. The 152-test focused producer/channel compatibility group passes,
as do the 20 T-02/migration PostgreSQL cases; `git diff --check` passes. Build runner
completed with its existing Drift circular-deserialization warnings while producing the
required Freezed/Injectable outputs.

## Context reset — T-04

**Task packet:** migrate every Part D existing producer and retained legacy kind to
`TransactionalAttentionCase`, one command at a time. Each mutation and receipt write
must share the UoW; delete the matching legacy `unawaited` notification call in the same
change. Destructive decline/removal/admission-loss commands resolve and snapshot their
recipient before the destructive statement. Do not add the three pending T-05 producers
or GraphQL/client behavior yet.

**Acceptance evidence required:** no existing event command has both legacy and new
receipt paths or neither; the C2 inventory covers `AuthCase`, `CredentialAuthCase`,
`InvitationCase`, `HelpOfferCase`, `ForwardCase`, `CoordinationCase`, all producing
coordination-item cases, `EvaluationCase`, and `BeaconRoomCase`; `ContactCase` remains
non-producing. Per-kind tests assert transactional receipt projection, and destructive
tests prove the pre-mutation audience survives. Existing command/channel behavior stays
green.

**Prerequisite evidence:** T-03 complete as recorded above.

**Unexpected findings:**

- Making `AttentionIntentCase` and `TransactionalAttentionCase` constructor parameters
  statically required exposed hundreds of read-only fixtures that instantiate producer
  cases through their retained legacy positional notification port. The compatibility
  seam remains: the positional port is retained, the two attention dependencies are
  optional named parameters, and every producing path uses null assertions. Production
  DI supplies both dependencies, while a misconfigured producing fixture fails closed;
  there is no legacy fallback or silent no-op.
- Injectable 3.1 compares nullable optional dependency types against non-null
  registrations with nullability intact and falsely reported both attention cases as
  unregistered even though its generated wiring was correct and ordered. Both cases are
  `@Singleton(order: 1)` ahead of order-2 consumers, and `app/di.dart` narrowly lists
  only their source libraries in `ignoreUnregisteredTypesInPackages`. Regeneration now
  emits no Injectable warning; the existing Drift circular-deserialization warnings
  remain.

**Resolution:** migrated `AuthCase`, `CredentialAuthCase`, `InvitationCase`,
`HelpOfferCase`, `ForwardCase`, `CoordinationCase`, every producing coordination-item
case, `EvaluationCase`, and `BeaconRoomCase` to `TransactionalAttentionCase.runAction`.
Each producer records a typed `AttentionDispatchIntent` inside the mutation UoW and
uses the existing post-commit channel boundary. The architecture inventory bans legacy
notification calls and detached producer writes across domain use cases and proves
`ContactCase` remains non-producing. `AttentionIntentCase` has a table-driven fixture
for every non-pending compact-contract event type. Decline/removal admission coverage
asserts recipient context is loaded before the destructive mutation.

**Verification:** the coordination-item suite passes all 163 tests; the full server
domain use-case/evaluation group passes all 591 tests; the T-04 inventory, projection,
and admission proof passes all 36 tests; the attention/contract/resolver group passes
all 41 tests; and the PostgreSQL migration plus attention atomicity group passes all 23
tests. Server and client Updates/realtime contract tests pass. Full server analysis
exits zero with the repository's existing warning/info baseline, and scoped analysis
has no warnings. Build runner succeeds with only the existing Drift warnings and no
Injectable warning. `git diff --check` passes.

## Context reset — T-05

**Task packet:** add only the new gated `roomMessagePosted`,
`requestStatusChanged`, and `mutualConnectionFormed` producer classes from Part D.
Directed Chat semantics are mention/reply/declared targets only; status coverage must
include every interactive transition plus actor-null expiry work wired through
`TaskWorkerCase`; reciprocal connection formation and invite acceptance produce while
unilateral removal, negative trust changes, ordinary Chat, and `ContactCase` do not.
The server gate is `ATTENTION_V1_NEW_PRODUCERS_ENABLED`, default false outside QA.

**Acceptance evidence required:** identity and dedup recipes permit
repeat-after-reversal; destructive transitions snapshot their audience; watcher
receipts are bounded, collapsed, and never pushed; mention/reply parsing and exact
message/thread targets pass; every excluded path has a negative producer test; all
three compact-contract rows move from `pending` to enforced only after their producer
and test inventory is complete.

**Prerequisite evidence:** T-04 complete as recorded above.

**Unexpected findings:**

- `EvaluationCase` is registered before same-order optional consumers in the generated
  graph. The first T-05 codegen run therefore placed `EvaluationCase` ahead of its
  optional `AttentionExpirySweepCase` dependency, which would have failed at runtime.
  The expiry case is now order 1 alongside the attention foundations, so generated DI
  registers `AttentionIntentCase`, `TransactionalAttentionCase`, and the expiry sweep
  before `EvaluationCase` and `TaskWorkerCase` resolve them.
- The existing review-window close implementation entered a nested author-scoped
  mutation for its lifecycle event even when the transition had no actor. An actor-null
  system UoW would correctly reject that mismatch. The lifecycle-event helper now writes
  directly in the surrounding system transaction when `actorId` is null; actor-owned
  paths retain their mutating-user scope.

**Resolution:** added the default-off
`ATTENTION_V1_NEW_PRODUCERS_ENABLED` environment gate, including a focused resolver
test. `BeaconRoomCase.createMessage` records only explicit mentions, same-scope reply
authors, or a directed coordination-item target, retains exact message/thread identity,
and rejects cross-scope replies; ordinary Chat remains receipt-free. Status producers
cover `BeaconCase` cancel/delete, `CoordinationCase.setBeaconStatus`, all interactive
`EvaluationCase` transitions, and a new actor-null `AttentionExpirySweepCase` invoked
by `TaskWorkerCase`; active participants receive standard channel-eligible receipts,
while watcher-only Inbox stances receive noisy per-Request-collapse receipts with no
channel decision. `UserTrustEdgeCase` records only a genuine reciprocal formation:
the repository serializes the unordered user pair with an advisory transaction lock,
compares the old and reverse vote, and permits a new receipt after reversal. The three
compact-contract event types are now enforced rather than pending.

**Verification:** 132 focused server tests pass, including exact directed-message,
ordinary-Chat, pre-destruction audience, status no-op/reversal, actor-null expiry,
gate-off, and reciprocal-only coverage. The disposable PostgreSQL attention suite
passes all 8 cases, including durable watcher-only receipt plus zero channel decisions.
Server and client Updates-contract tests pass. Scoped server analysis exits zero with
only the repository's existing infos. Build runner succeeds with the existing Drift
circular-deserialization warnings and emits the corrected DI order. `git diff --check`
passes before T-06 begins.

## Context reset — T-06

**Task packet:** expose only thin V2 controllers over the established attention query,
acknowledgement, and preference ports: bounded `attentionFeed`, `attentionMarkSeen`,
`attentionMarkAllSeen`, in-app preference read/update, and authorized exact
`roomMessageTarget` hydration. Keep legacy `notifications*` shape intact. Register
every operation in the client direct-operation allowlist and generate code; do not
start the flagged client application/UI slice.

**Acceptance evidence required:** controller authorization and payload allowlists;
opaque cursor and id-list bounds; preference rejection for unknown/non-muteable keys;
legacy-field regression; direct-routing registration; exact message target positive and
unauthorized negative coverage.

**Prerequisite evidence:** T-05 complete as recorded above.

**Unexpected findings:**

- The existing room enrichment API only accepted a paged thread query. Reusing it for
  an exact link would have made old targets disappear outside the first page. The
  repository now applies a message-id filter before enrichment, keeping target
  hydration to one authorized row.
- `NotificationCenterCase` must preserve its legacy shape while moving read/ack onto
  the authorized attention relation. Its old `before` cursor is timestamp-only, so it
  remains a compatibility cursor; the new V2 feed is the only composite opaque cursor
  API.
- Injectable 3.1 also reports nullable attention ports in the compatibility case as
  missing despite emitting valid registrations. The existing narrowly scoped DI
  workaround now lists those two port types/source files; generated wiring retains the
  concrete ports.

**Resolution:** added `attentionFeed(view, cursor, limit)` with a validated base64url
composite cursor, receipt projection, typed destination, presentation key/payload, and
one atomic port call. `attentionMarkSeen` caps ids at 200 and `attentionMarkAllSeen`
delegate directly to `AttentionAckPort`. Existing notification preferences now expose
and validate `mutedInAppEventClasses` against the two contract-owned noisy classes.
Legacy `NotificationCenterCase` uses the authorized feed/ack ports in production while
retaining its GraphQL field names and item shape. `roomMessageTarget` loads the exact
message, authorizes its actual main-room or item-thread scope, and returns only its
enriched row. Client schema/documents and the direct-operation allowlist cover all six
new/direct V2 operations; no client application slice or UI was added.

**Verification:** server build runner completed with the known Drift
circular-deserialization warnings and generated Ferry/Injectable outputs. The focused
36-test server set passes: V2 controller auth/cursor/payload/id-bound tests, preference
validation, legacy Notification Center regressions, and authorized/unauthorized exact
room targets. Scoped server analysis exits zero with the repository's pre-existing
infos/warning baseline; scoped client analysis exits zero with three pre-existing infos.
`git diff --check` passes.

## Context reset — T-07

**Task packet:** prove shadow parity and the invalidation budget without comparing
unlike projections. A mismatch in dual-write read axes over the same guarded legacy
page is unexplained; authorization, new-event-class, and muted-noisy deltas are
separately labeled. Preserve the statement-level 1/50/500 PostgreSQL budget and record
its scope in the realtime runbook.

**Unexpected findings:** T-08 has not yet introduced `AttentionCase`, the sole client
refresh owner. Therefore the existing PostgreSQL 1/50/500 proof demonstrates one wire
hint per account per SQL statement, but cannot honestly demonstrate the client-side
maximum of one in-flight plus one queued attention refresh. The runbook explicitly
records this boundary instead of claiming full client convergence early.

**Resolution:** added the default-off QA gate `ATTENTION_V1_SHADOW_ENABLED` and
`AttentionShadowCase`. On legacy Notification Center feed reads it independently loads
the same legacy guarded page and an authorized attention page, compares `read_at` with
the compatibility `seen_at` axis on common receipts, and emits aggregate-only
`attention_event=shadow_delta` classifications or `attention_event=shadow_mismatch`
for unclassified/read-axis divergence. The GraphQL response is never delayed or changed
by the telemetry. `docs/realtime-sync-operations.md` now distinguishes the proven PG
budget from the T-08 client refresh proof.

**Verification:** `AttentionShadowCase` classification tests and environment gate tests
pass. The disposable PostgreSQL migration/attention suite passes all 24 cases,
including the exact 1/50/500 acknowledgement hint test; V2 controller tests also pass.
Build runner completed with the known Drift warnings and `git diff --check` passes. The
five-run T-15 release proof enabled `ATTENTION_V1_SHADOW_ENABLED=true` and its 121,059
line server log contains no `attention_event=shadow_mismatch` or
`attention_event=shadow_failure` marker. T-07 is complete; client refetch budget proof
is owned by the completed T-08 refresh owner.

## Context reset — T-08

**Task packet:** create the UI-independent attention application slice under
`lib/domain/attention/`, bind its concrete Ferry repository outside the domain, and
make it the sole owner of notification hint/catch-up refreshes. The compile-time
`UPDATES_TAB_ENABLED` gate must be default-off and prevent both subscriptions and
queries in disabled builds. Do not add visible Updates UI before T-10.

**Resolution so far:** added Freezed receipt/summary/feed entities,
`AttentionRepositoryPort`, `AttentionAccountPort`, and an auth-domain account adapter.
`AttentionCase` is lazy and inert while the flag is off. When enabled it partitions
its normalized receipt/page cache and optimistic acknowledgement store by account
generation, drops stale A-to-B responses, and converts notification hints/catch-ups
into a head refresh with at most one in-flight request plus one queued rerun. The
concrete repository maps only generated Ferry V2 data to domain entities and uses the
already direct-routed `AttentionFeed`, `AttentionMarkSeen`, and
`AttentionMarkAllSeen` operations. The realtime contract now declares
`updates_feed` and `updates_badge` impacts while retaining legacy Notification Center
impacts.

**Verification so far:** client focused tests pass for the 1+1 refresh bound,
catch-up, account reset/stale response rejection, optimistic acknowledgement
reconciliation, acknowledgement-store reset, and disabled no-query behavior. Client
and server realtime-contract tests pass; the client domain-boundary test rejects data
and UI imports under `lib/domain/attention/`. Client build runner completed.

**Verification:** client build runner regenerated Freezed and Injectable output. The
generated DI graph registers the repository, auth adapter, and case lazily, so the
default-off build neither constructs the attention slice nor creates its subscriptions.
Focused client tests and scoped client analysis pass; server and client contract tests
pass, and `git diff --check` passes. T-08 is complete. T-07 still requires its enabled
QA shadow soak before its separate acceptance claim.

## Context reset — T-09

**Task packet:** eliminate Home-shell positional-index ownership without changing the
visible four-tab application. A stable spec must own each tab's index, branch path,
shell, root-route reset, deep-link owner, and active-tab comparisons so the later
Updates insertion cannot shift Network or Profile behavior.

**Resolution:** added `HomeTab` and `HomeTabSpec` in the router boundary. The spec
owns the existing Work/Inbox/Network/Profile index, path, shell, and root route. Home
shell routes, root redirect/cold-owner resolution, deep-link branch prefixes, reselect
resets, post-join index assertions, and Home test-shell routes now derive from it.
`NewStuffState` stores semantic `HomeTab`, and its dot checks, shell listener, Inbox
snackbar dismissal, and navbar selectors no longer compare active indices to literals.
The fourth/fifth route ordering has not changed; T-10/T-11 remain responsible for the
flagged Updates presenter and visible fifth branch.

**Verification:** `dart run build_runner build -d` completed. The focused 35-test
router/Home/New Stuff suite passes, including branch restore, cold/warm redirects,
deep-link prefixing, and reselect-to-root behavior. A new architecture test asserts
the four current mappings and rejects positional active-index comparisons in Home tab
consumers. Scoped client analysis and `git diff --check` pass.

## Context reset — T-10

**Resolution:** added the default-off `features/updates/` presenter. `UpdatesFeedCubit`
only projects `AttentionCase.feedPages`, owns view selection and pagination commands,
and never queries a repository directly. `UpdatesScreen` is route-free until T-11 and
returns no UI when `UPDATES_TAB_ENABLED` is false. The presenter supplies All/Unread
underline views, stale-content-preserving pull-to-refresh, page-storage scroll keys,
near-end pagination, flat receipt rows, initial loading, and neutral All/Unread empty
states. EN/RU strings are generated from the l10n ARBs.

**Verification:** `flutter gen-l10n`, `dart run build_runner build -d`, scoped Updates
analysis, and focused presenter-state test pass. T-11 remains responsible for branch
registration and exact destination navigation; T-12 adds acknowledgement UI actions.

## T-14 — Full-stack release proof

The local multi-client runner now starts an attested server with
`ATTENTION_V1_NEW_PRODUCERS_ENABLED=true`,
`ATTENTION_V1_SHADOW_ENABLED=true`, and actor echo enabled, compiles web with
`UPDATES_TAB_ENABLED=true`, and writes those gates to `release-gates.json`.
The browser journey settles bootstrap-only attention, verifies the author badge moves
from 0 to 1 after a helper offer, opens the Updates card to the People target, and
verifies both author sessions converge to badge 0. The shell badge is sourced from the
domain-owned attention summary and has a semantic identifier for the browser proof.

**Release artifact:** `reports/realtime-multiclient/updates-t14-release-20260717-005719`.
Five consecutive passes completed with negative live-delivery and catch-up proofs.
P95s: Updates delivery 282 ms, Updates open-ack 16 ms, connected delivery 1409 ms,
and reconnect catch-up 1714 ms. The enabled shadow telemetry recorded no unexplained
`attention_event=shadow_mismatch` or `attention_event=shadow_failure` markers.

## T-15 — Unconditional flip release proof

The final runner removes the retired client/server defines and attests
`updates_tab: "unconditional"` plus `attention_v1_new_producers: "unconditional"`.
Its expected offline Chat error is dismissed through the snackbar's semantic close
control before retrying, so the retry proves application recovery rather than clicking
through the 15-second error surface. Artifact paths are canonicalized before the
runner changes into the client package.

**Release artifact:** `reports/realtime-multiclient/updates-t15-release-20260717` at
revision `0dde7ecf`. Five consecutive positive runs and both disabled live/catch-up
negative controls passed. P95s: Updates delivery 233 ms, Updates open-ack 33 ms, Chat
delivery 773 ms, and reconnect catch-up 1695 ms.

## T-18 — Search & filters

Added a bounded `attentionFeed(search:)` argument, normalized to a trimmed nullable
value with a 120-character cap. The feed searches only the authorized receipt relation
and only its locale-neutral allowlisted structured payload fields: event type, Request,
coordination item, target entity, and message identifiers. It does not search channel
title/body copy. The client debounces the Updates search field, and its domain case
retains the normalized query across cursor pagination.

Migration `m0119` adds the matching GIN expression index. PostgreSQL rejected the
initial `concat_ws` expression because it is not immutable, so the final index and
query use immutable `coalesce(...) || ' ' || ...` concatenation instead.

**Verification:** PostgreSQL repository coverage proves authorization before search,
payload-only matching, stable opaque cursor paging, and index use under an EXPLAIN
plan. Migration and GraphQL controller suites pass, as do the focused client domain
case and scoped server/client analysis. T-18 is complete.

## T-19 — Legacy contract phase

Raised the client and server major versions to `5.0.0` and `2.0.0` respectively, and
the deployable `MIN_CLIENT_VERSION` example to `5.0.0`. Production deployment must set
the same environment variable before shipping this contract-breaking server release.

Migration `m0120` creates the seen-only dedup and unread indexes before dropping their
transition predecessors, then restores the established index names. Active feed,
acknowledgement, directed-Chat watermark, and collapse paths now use `seen_at` only;
`read_at` remains retained historical data and is no longer written. The legacy
`notifications*` GraphQL fields, Notification Center use case, shadow comparator, and
stale client GraphQL inputs are removed. Room push dispatch remains the post-commit
channel boundary, not a legacy read-model API.

**Unexpected finding:** T-15 had removed visible Notification Center chrome but the
server GraphQL registrations and client query inputs were still present. T-19 removes
that dormant compatibility surface. The initial collapse regression test mistakenly
set `seen_at`, which correctly opened a new receipt; it now separately proves that a
`read_at`-only change does not reopen a collapse window, while `seen_at` does.

**Verification:** PostgreSQL migration/index/collapse/acknowledgement and authorized
attention repository suites pass alongside attention GraphQL tests. Server analysis,
client code generation, and client analysis complete with the repository's existing
informational warning baseline. T-19 is complete.

## T-20 — Occurrence store + durable channel delivery (in progress)

The existing post-commit channel hand-off is an in-memory attempt, not a delivery
record. T-20 separates immutable occurrence identity (`source_event_key`), event-time
recipient snapshots, mutable collapsed receipts, and durable delivery jobs. Jobs will
freeze send context, use leases and bounded retries/dead letters, and reserve
per-account channel throttles.

`m0121` is the additive storage foundation. Producer and worker wiring is deliberately
pending its PostgreSQL failure/recovery proof so no half-migrated dual-send path ships.

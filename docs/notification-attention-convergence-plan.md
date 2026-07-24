# Notification / Attention Convergence — Careful Migration Plan

Status: Draft for review · Date: 2026-07-24 · Schema tip: m0124

**Goal:** finish the in-flight migration so the notification stack has *one* receipt-creation path
and a slimmer, non-schizophrenic `notification_outbox`, **without breaking the currently-working,
fragile notification mechanism.** Application and contract changes are designed to be behavioral
no-ops for readers, verifiable, and independently revertible. **Step 5** is the explicit exception:
it deletes pre-real-user legacy receipts, which the project owner has confirmed carry no real-user
compatibility obligation. (**Step 6** is the other non-reversible point — see §9.6.)

> **This plan was rewritten on 2026-07-24 to incorporate the Appendix A critical review (CR-1 … CR-14).**
> The earlier draft's Stage 1 ("migrate two legacy producers onto the dispatch repository") was
> **wrong** and has been removed — those services are dead compatibility surfaces, not live
> producers (CR-1/CR-2, verified against the live tree). See Appendix A for the resolution log.

Row-count figures below are a **local snapshot from 2026-07-24**, not production evidence. Every
production rollout gate needs an environment-labelled, timestamped query/metric before it counts.

---

## 1. Current live topology (what we must not break)

The system runs **five** attention/notification tables and **two receipt-creation surfaces** (one
live, one dead). This is the reality on disk, confirmed by live counts and static tree.

**Stores**
- `attention_occurrence` (218) — append-only event, idempotent on `source_event_key`.
- `attention_occurrence_recipient` (228) — per-occurrence audience snapshot.
- `attention_channel_delivery` (228) — job ledger that **durably retries the channel *handoff
  attempt*** (lease + dead-letter). It does **not** prove provider acceptance or end-to-end
  push/email delivery — see CR-8.
- `attention_channel_throttle` (19) — per-account/channel lease. (Was omitted from the earlier
  draft.)
- `notification_outbox` (750; **419 legacy / 331 new-shape**) — the **read model** for the feed,
  badges, and email digest. *Not dead, not just history* — the canonical writer materializes into
  it on every event.

**Receipt-creation surfaces**
- **Canonical (live):** the domain use cases build `AttentionDispatchIntent`s and call
  `AttentionTransaction.record()` **inside their own mutation transaction** (via
  `TransactionalAttentionCase`). `AttentionDispatchRepository.record()` writes occurrence →
  recipient snapshot → `notification_outbox` receipt → channel-delivery job in that caller-owned
  transaction.
- **Dead compatibility (to prove-dead and remove):** `NotificationOutboxRepository.enqueue()` and
  its two adapters `InviteAcceptedNotificationService` and `BeaconNotificationService._writeOutbox`.
  Their public entry methods (`notifyInviteAccepted`, `BeaconRoomNotificationPort.notify*`,
  `BeaconNotificationPort.dispatch`) have **no production call sites**; use cases still receive the
  ports as unused constructor params named `legacyNotificationPort`. See CR-1.

**Read / consumer surfaces (the contract that must keep working):**
1. **Client feed** — custom server resolver `attentionFeed` (`attention_feed.graphql`), *not* a raw
   Hasura table. Selects both legacy fields (`title, body, actionUrl, category, kind, priority`)
   **and** new fields (`sourceEventKey, destinationKind, presentationKey, requiresAction,
   attentionThreadKey, settlementKind, settledAt`). The legacy fields are live fallback
   presentation — **not droppable.**
2. **Markers / badges** — `attentionMarkers`, `attention_mark_seen`, `attention_mark_all_seen`,
   `attention_settle`. Backed by `visible_attention_receipts`.
3. **Email digest / immediate email** — `email_digest_case` via `NotificationOutboxRepository`,
   which also **marks emailed, computes cooldown counts, and deletes retained receipts** — a mixed
   lifecycle port, not a read-only adapter (CR-7).
4. **Realtime** — `notify_notification_outbox_{insert,update,delete}` → generic
   `emit_realtime_entity_change('notification', account_id, …)`, wrapped in
   `EXCEPTION WHEN OTHERS … RAISE WARNING … RETURN NULL`. **Preserve that fail-open wrapper.**
5. **Push channels** — `attention_channel_delivery` drained by `AttentionChannelDeliveryCase`, which
   calls `BeaconNotificationPort.handOffChannels()` — **this method is live and must be preserved**
   even though the rest of `BeaconNotificationService` is dead.

---

## 2. Guiding principle: single *creator*, then expand/contract

The excess complexity is **not** "too many columns" (only `digested_at` is verified dead) and
**not** "two live writers." It is: (a) a **dead second receipt-creation surface** still wired into
every use case, and (b) `notification_outbox` carrying **two row shapes** whose split is policed by
**one** constraint, `__new_shape_chk`.

Terminology, used precisely throughout: the target invariant is **one receipt creator/materializer**
— *not* one writer to the whole table. Acknowledgement, Chat-watermark bridging, settlement,
email/digest bookkeeping, collapse, and retention legitimately mutate `notification_outbox` and are
not being centralized (CR-7).

**Never** drop or retype a column while any writer emits the old shape or any reader selects it.
Every schema contraction lands only after a bake period with zero legacy creation **and** a
production preflight proving zero violating rows and that old binaries cannot write (CR-5).

---

## 3. Do-not-touch invariants

- **Do not** collapse the five tables into fewer. The occurrence → recipient → delivery separation
  is the intended topology; but it is only "robust" once §4-step-4 lifecycle work lands (CR-4).
- **Do not** drop `title/body/action_url/category/kind/priority` — live feed fallback.
- **Do not** remove the `notify_*` triggers' `EXCEPTION … RETURN NULL` fail-open wrapper.
- **Do not** change the `attentionFeed` / `attentionMarkers` output shape — the client contract.
- **Do not** create a *second* call to `record()` from a data adapter — `record()` requires a
  caller-owned mutation transaction and a persisted causation identity for `source_event_key`;
  only the domain use case satisfies that (CR-2).
- **Do not** treat `dedup_key` (account-namespaced partial-unique conflict key on the mutable
  receipt) and `attention_occurrence_recipient.collapse_key` (immutable snapshot fact) as
  redundant — different relations, identities, and lifetimes (CR-10).

---

## 4. Corrected staged sequence

Ordered per the Appendix A review. Each step is one or more small PRs/migrations; **do not batch across
step boundaries.**

### Step 1 — Reconcile the architecture contract (docs only, no code)
- ADR-0010 still states the occurrence/audience/durable-delivery tables are *deferred* and v1 uses
  only `notification_outbox`; the archived journal says T-20 is complete. Amend or supersede
  ADR-0010 with an accepted decision record covering: the actual handoff-job guarantee (CR-8),
  `source_event_key`/audience-snapshot identity (CR-9), collapse semantics, retention, and
  account-erasure behavior, and operational ownership of pending/dead jobs and throttle leases
  (CR-14).
- Label all row-count evidence used as rollout gates by environment + timestamp.

### Step 2 — Prove and remove the dead compatibility wiring (application layer)
No schema change; this is "finishing it" done correctly.
- Add a **static architecture test** asserting no production source under `packages/server/lib`
  calls the legacy creation API (`enqueue()`), `notifyInviteAccepted`,
  `BeaconRoomNotificationPort.notify*`, or `BeaconNotificationPort.dispatch()` (CR-12).
- Then delete, in order: the unused `legacyNotificationPort` / `roomPush` constructor params;
  `InviteAcceptedNotificationPort` + `InviteAcceptedNotificationService`; `BeaconRoomNotificationPort`
  + `BeaconRoomPushService`; the `BeaconNotificationPort.dispatch()` method and
  `BeaconNotificationService.dispatch()` / `_writeOutbox()` branch.
- **Preserve** `handOffChannels()` behind a narrowed, channel-handoff-only port (CR-1). Do not
  delete or repurpose the whole service; do not add a new `record()` caller.
- **Exit gate:** static test green; full server + feed/email/push suites green.

### Step 3 — Retire only the legacy receipt-creation method
- Delete `NotificationOutboxRepository.enqueue()` and the `enqueue` port method (no callers after
  Step 2). Rewrite its migration/characterization tests to the new expectation.
- **Keep** the email/immediate-email/digest/retention methods. Either keep the class one release or
  split into narrow domain-owned ports (digest/email bookkeeping; retention). **Do not** fold this
  mixed lifecycle into `AttentionRepository` (CR-7).
- **Exit gate:** one full release running single-creator with no incidents.

### Step 4 — Repair lifecycle correctness (prerequisite to any contraction)
The normalized topology cannot be blessed as robust until this lands (CR-4, CR-9).
- **Account erasure:** `attention_occurrence_recipient.account_id`,
  `attention_channel_delivery.account_id`, and `attention_channel_throttle.account_id` reference
  `"user"(id)` `ON DELETE RESTRICT`; `UserCase.deleteById()` has no attention cleanup, so
  `userDelete` can fail for accounts that received canonical attention (101 recipient accounts
  locally). Specify and test the FK-safe erasure order: throttle → delivery → receipt → recipient
  snapshot → occurrence. Add a real PostgreSQL `userDelete` integration test.
- **Retention:** `attention_channel_delivery.receipt_id` → `notification_outbox(id)`
  `ON DELETE RESTRICT`; the bulk `deleteSettledOlderThan()` can abort the whole sweep on one
  restricted row. Fix the delete order and add a retention test containing **both** legacy and
  delivery-backed receipts.
- **Idempotency identity:** `record()` treats a `source_event_key` conflict as a replay when only
  `immutable_payload` matches — it ignores `event_type`, `actor_user_id`, and the recipient
  ids/reasons/role-facts/collapse-keys/eligibility. Define exactly which occurrence + audience facts
  are part of idempotency equality and add PostgreSQL mismatch tests for each (CR-9).
- **Exit gate:** erasure, retention, and idempotency-mismatch tests pass.

### Step 5 — Delete the pre-real-user legacy receipts
- **Decision (2026-07-24, project owner): delete, not age out, not backfill.** Tentura has no real
  users; the 419 legacy rows (all `seen_at IS NULL`, 418 currently visible via
  `visible_attention_receipts`, none older than 30 days) are pre-real-user/test data. Existing
  retention would **not** remove them (`attentionFeed` has no time window; `deleteSettledOlderThan`
  only touches `seen_at IS NOT NULL`).
- After Step 3's bake gate: record the before count, delete all `access_policy='legacy'` rows in an
  explicit transaction, verify after count is zero. No synthetic provenance is fabricated.
- This is an **intentional visible feed/badge reset**, not a behavioral no-op or natural retention.
  **Gate:** if real-user onboarding starts before this lands, the authorization expires and the
  deletion must be re-reviewed.

### Step 6 — Close the rollback window, then contract the shape
This DDL makes an old server binary unable to write, so it is **not independently revertible** —
add an explicit mixed-binary/rollback gate and name the point where the deployment moves from
reversible to forward-fix-only (CR-5).
- Preflight (production, environment-labelled): prove zero `access_policy='legacy'` rows and zero
  rows violating the target `NOT NULL`s.
- `ALTER COLUMN access_policy DROP DEFAULT` (do **not** substitute another default — a real policy
  is per-event and must be supplied explicitly by the creator; CR-5); retain `NOT NULL`; remove
  `'legacy'` from `__access_policy_chk`.
- Remove **`__new_shape_chk`** — the *only* pure split-policing constraint. **Do not** remove the
  other checks (access-policy allow-list, beacon-policy prerequisite, `recipient_safe` allow-list,
  suppression/preference consistency, settlement-fact consistency, thread-key structure): each is a
  live domain/security invariant (CR-6).
- Add `NOT NULL` to `source_event_key`, `destination_kind`, `presentation_key` (always set by the
  sole creator now).
- **Exit gate:** preflight clean; `__new_shape_chk` gone; feed/email/push suites + realtime
  multi-client proof green.

### Step 7 — Drop dead columns individually (smallest, last)
- `digested_at` — **0 live refs**, its own migration + test.
- `read_at` — treat as a **compatibility/trigger cleanup**, not a "digest can key off seen_at"
  swap. It still lives in `NotificationOutboxRepository` mapping, the domain entity, the m0116
  realtime update trigger's changed-row tuple, and compat tests; `seen_at` has been the live
  unread/collapse axis since m0120. Gate = mixed-binary compatibility + removing those mappings and
  updating the trigger; record the exact dependency inventory and expected realtime behavior first
  (CR-11).
- **Leave `dedup_key` and `collapse_key` alone** — not redundant (CR-10). Removing either needs a
  separate approved identity/replay/collapse/retention design.

---

## 5. Stage-0 evidence & test scaffolding (runs before Step 2)
- **Legacy-usage metric (CR-12):** instrument invocations of the legacy `enqueue()` API (or its two
  adapters) **by build and call site** — not a DB `access_policy='legacy'` count, which misses
  `ON CONFLICT DO UPDATE` collapses into an existing unseen legacy row and cannot recover a producer
  tag. Separately observe resulting insert/update rows. Define "full digest cycle" numerically
  (daily vs weekly settings otherwise make the gate ambiguous).
- **Compatibility fixture (CR-13):** assert **semantic** equality (not serialization byte-equality)
  across authorization/tombstone rendering, legacy + canonical presentation fields, unread/Needs-you
  summary counts, cursor ordering + collapse count, ack/mark-all/settlement, email eligibility +
  immediate-email bookkeeping, and realtime account targeting. Keep a **client** parsing/rendering
  fixture for a legacy receipt too — the server resolver test alone cannot prove identical client
  behavior.

## 6. Existing safety nets to lean on
- `attention_repository_pg_test.dart`, `beacon_notification_service_test.dart`,
  `email_digest_case_test.dart`, `task_worker_case_test.dart`.
- `realtime_notification_migration_test.dart` + `realtime_entity_contract_test.dart` (NOTIFY
  contract).
- `reports/realtime-multiclient/updates-*` browser proofs (T-21 marker harness).
- ADR-0010 + `docs/contracts/updates-event-contract.json` — but see Step 1: ADR-0010 must be
  amended before the topology is declared permanent.

## 7. Net effect (once Steps 1–5 land)
- One live receipt creator; the dead compatibility surface and its ports/params gone.
- `notification_outbox` stops being a two-shape hybrid; **one** constraint removed
  (`__new_shape_chk`) and one allow-list narrowed — *not* "~6 constraints removed."
- Account erasure and retention become FK-safe and tested; canonical idempotency equality is
  specified and tested.
- Robustness improves for **receipt creation**; channel delivery remains a durable **handoff**
  guarantee (unchanged, not upgraded to provider-accepted). No client/feed/email/push
  **contract-shape** change; Step 5 intentionally removes pre-real-user data and is not a no-op.

---

## 9. Autonomous implementation guide (turnkey, per-step)

This section is written so an implementer can execute each step mechanically. **Do the steps in
order. After every step, run the "verify" block; if any check fails, STOP and do not continue.**
All paths are repo-relative from the project root `/…/tentura`.

### 9.0 Ground rules (apply to every step)

- **Never hand-edit generated files.** `*.g.dart`, `*.freezed.dart`, and
  `packages/server/lib/app/di.config.dart` are regenerated. After any change to Injectable
  wiring (adding/removing a `@Singleton`/`@LazySingleton`/`@injectable` class, or changing a
  use-case constructor), regenerate:
  ```bash
  cd packages/server && dart run build_runner build -d
  ```
- **Test commands** (from `packages/server`):
  ```bash
  dart analyze                        # must be clean (no errors) before committing a step
  dart test --exclude-tags pg         # unit suite (CI gate)
  dart test --tags pg                 # integration; needs local Postgres reachable
  ```
  Postgres integration tests connect via env, defaults `127.0.0.1:5432`, user `postgres`,
  password `password`, admin db `postgres` (see `test/**/*_pg_test.dart`). The local dev DB in the
  `postgres` docker container satisfies this.
- **One step = one commit = one PR.** Do not batch across step boundaries. Branch off `main`
  (never commit directly to `main`).
- **Migrations are append-only and immutable once merged.** Never edit an existing `mNNNN.dart`.
  To register a new migration `mNNNN` you must edit **two** places in
  `packages/server/lib/data/database/migration/_migrations.dart`:
  1. add `part 'mNNNN.dart';` after the last existing `part` line;
  2. add `mNNNN,` at the end of the `InMemory([ … ])` list.
  A migration file is:
  ```dart
  part of '_migrations.dart';

  /// <one-line intent>.
  final mNNNN = Migration('NNNN', [
    r'''<SQL statement 1>''',
    r'''<SQL statement 2>''',
  ]);
  ```
  where `NNNN` is the zero-padded number (e.g. `'0125'`). The next free number is **m0125**
  (current tip is m0124).
- **STOP conditions that abort the whole plan:** (a) real-user onboarding has started (invalidates
  Step 5); (b) any "verify" block fails and you cannot make it pass without changing a read
  contract in §3; (c) a production preflight query in Step 6 returns a non-zero violating-row count.

### 9.1 Step 1 — ADR reconciliation (docs only)

- Edit `docs/adr/0010-attention-receipt-extension.md`: append a "Superseded for T-20" note, or add
  a new `docs/adr/0011-attention-durable-topology.md`, recording: the handoff-job guarantee is a
  **durable handoff attempt, not provider-accepted delivery** (see Step 4 / CR-8); the idempotency
  identity fixed in Step 4; retention + account-erasure behavior from Step 4; ownership of
  pending/dead delivery jobs and throttle leases.
- **Verify:** the ADR names the five tables (`attention_occurrence`,
  `attention_occurrence_recipient`, `attention_channel_delivery`, `attention_channel_throttle`,
  `notification_outbox`) and no longer claims the durable topology is "deferred / not in v1".
- No code, no tests.

### 9.2 Step 2 — Delete the dead compatibility wiring (application layer, no schema change)

**Delete these files entirely:**
- `packages/server/lib/domain/port/invite_accepted_notification_port.dart`
- `packages/server/lib/domain/port/beacon_room_notification_port.dart`
- `packages/server/lib/data/service/invite_accepted_notification_service.dart`
- `packages/server/lib/data/service/beacon_room_push_service.dart`
- `packages/server/lib/domain/entity/invite_accepted_notification_intent.dart` — **only if**
  `grep -rIn "InviteAcceptedNotificationIntent" packages/server/lib` shows no remaining refs after
  the above deletions.

**Edit `packages/server/lib/domain/port/beacon_notification_port.dart`:** remove the `dispatch(...)`
method and its `BeaconNotificationIntent` import if now unused. Keep `handOffChannels(...)`. The
port becomes handoff-only.

**Edit `packages/server/lib/data/service/beacon_notification_service.dart`:** remove the
`@override dispatch(...)` method and the private `_writeOutbox(...)` method. Then run
`dart analyze` and remove every field/import/helper it now reports as unused (expected: the
recipient-resolver, copy-builder, room-context, and `NotificationOutboxRepositoryPort _outbox`
dependencies that only `dispatch`/`_writeOutbox` used — remove those constructor params too). Keep
everything `handOffChannels` uses (FCM queue/remote/tokens, preferences, gate, email, logger). The
class must still be `@LazySingleton(as: BeaconNotificationPort)` and still implement
`handOffChannels`, because `AttentionChannelDeliveryCase` depends on it.

**Edit the use cases that take a vestigial notification port param.** For each file below, delete
the unused constructor parameter (`BeaconRoomNotificationPort legacyNotificationPort` /
`... roomPush` / `InviteAcceptedNotificationPort legacyNotificationPort`) and its now-unused
import. The bodies do not reference these params (verified), so no body change is needed:
`domain/use_case/forward_case.dart`, `coordination_case.dart`, `invitation_case.dart`,
`evaluation_case.dart`, `help_offer_case.dart`, `auth_case.dart`, `credential_auth_case.dart`,
`beacon_room_case.dart`, and under `domain/use_case/coordination_item/`:
`publish_draft_ask_case.dart`, `create_promise_case.dart`, `cancel_promise_case.dart`,
`resolve_blocker_case.dart`, `mark_blocker_case.dart`, `update_plan_case.dart`, `mark_ask_case.dart`,
`remind_coordination_item_case.dart`, `publish_draft_blocker_case.dart`,
`publish_draft_promise_case.dart`.
> Authoritative list = `grep -rIln "legacyNotificationPort\|roomPush" packages/server/lib/domain/use_case`.
> Trust the grep over this list if they differ.

**Add a guard test** `test/architecture/no_legacy_notification_producer_test.dart` that greps the
production tree and fails if any of these symbols reappear in a call position:
`NotificationOutboxRepositoryPort` `.enqueue`, `.notifyInviteAccepted`, `BeaconRoomNotificationPort`,
`BeaconNotificationPort` `.dispatch`. (Model it on the existing
`test/architecture/realtime_entity_contract_test.dart`.)

**Regenerate DI + verify:**
```bash
cd packages/server && dart run build_runner build -d && dart analyze && dart test --exclude-tags pg
```
- **Verify:** analyze clean; unit suite green; new guard test green; `git grep -n "\.dispatch("
  packages/server/lib/data/service` no longer shows notification dispatch; `AttentionChannelDeliveryCase`
  still compiles and its test passes.

### 9.3 Step 3 — Retire the legacy receipt-creation method (no schema change)

- Edit `packages/server/lib/data/repository/notification_outbox_repository.dart` and
  `packages/server/lib/domain/port/notification_outbox_repository_port.dart`: delete the `enqueue(...)`
  method from both. **Keep** all other methods (`markEmailed*`, `accountsWithPendingEmail`,
  `lastEmailedAt`, `pendingForAccount`, `countRecentEmailsByCategory`, `deleteSettledOlderThan`,
  `_mapRow`). Do **not** move these into `AttentionRepository`.
- Update/rewrite any test that exercised `enqueue` (search `grep -rIln "\.enqueue(" packages/server/test`).
- **Verify:** `dart analyze` clean; `dart test --exclude-tags pg` and `dart test --tags pg` green;
  the Step-2 guard test still green.

### 9.4 Step 4 — Lifecycle correctness (migration m0125 + code + pg tests)

**4a — FK migration.** Create `packages/server/lib/data/database/migration/m0125.dart` and register
it (§9.0). Content:
```dart
part of '_migrations.dart';

/// FK-safe account erasure and retention for the durable attention topology:
/// cascade account-scoped attention rows on user delete, and delivery jobs on
/// receipt delete. Occurrence rows are shared history and stay RESTRICT.
final m0125 = Migration('0125', [
  r'''ALTER TABLE public.attention_channel_throttle
        DROP CONSTRAINT attention_channel_throttle_account_id_fkey,
        ADD CONSTRAINT attention_channel_throttle_account_id_fkey
          FOREIGN KEY (account_id) REFERENCES public."user"(id) ON DELETE CASCADE;''',
  r'''ALTER TABLE public.attention_channel_delivery
        DROP CONSTRAINT attention_channel_delivery_account_id_fkey,
        ADD CONSTRAINT attention_channel_delivery_account_id_fkey
          FOREIGN KEY (account_id) REFERENCES public."user"(id) ON DELETE CASCADE;''',
  r'''ALTER TABLE public.attention_channel_delivery
        DROP CONSTRAINT attention_channel_delivery_receipt_id_fkey,
        ADD CONSTRAINT attention_channel_delivery_receipt_id_fkey
          FOREIGN KEY (receipt_id) REFERENCES public.notification_outbox(id) ON DELETE CASCADE;''',
  r'''ALTER TABLE public.attention_occurrence_recipient
        DROP CONSTRAINT attention_occurrence_recipient_account_id_fkey,
        ADD CONSTRAINT attention_occurrence_recipient_account_id_fkey
          FOREIGN KEY (account_id) REFERENCES public."user"(id) ON DELETE CASCADE;''',
]);
```
> Rationale: `notification_outbox.account_id → user` is *already* `ON DELETE CASCADE`; the four FKs
> above are the `RESTRICT` ones that abort `userDelete` and the retention sweep. Leave the two
> `*_occurrence_id_fkey` FKs as `RESTRICT` (occurrences are retained history and are never
> bulk-deleted).

**4b — Idempotency identity (CR-9).** In
`packages/server/lib/data/repository/attention_dispatch_repository.dart`, the conflict branch
(`ON CONFLICT (source_event_key) DO NOTHING` → the follow-up `SELECT … WHERE source_event_key=$1
AND immutable_payload=$2`) must also compare `event_type` and `actor_user_id`. Change that SELECT to
also match `event_type = $3 AND actor_user_id IS NOT DISTINCT FROM $4`, binding the intent's values;
if the row exists but any of those differ, keep throwing the existing `StateError`. Document in a
code comment that idempotency equality = `{source_event_key, event_type, actor_user_id,
immutable_payload}` at the occurrence grain.

**4c — Tests (`--tags pg`).**
- `test/domain/use_case/user_delete_attention_pg_test.dart`: seed a user who is the `account_id` of
  an `attention_occurrence_recipient`, an `attention_channel_delivery`, and an
  `attention_channel_throttle` row (and owns `notification_outbox` receipts); call the real user
  deletion path; assert it succeeds and those rows are gone.
- `test/data/repository/attention_retention_pg_test.dart`: with both a legacy receipt and a
  delivery-backed canonical receipt that are `seen_at IS NOT NULL` and older than the retention age,
  assert `deleteSettledOlderThan` removes them without aborting.
- Extend `test/data/repository/attention_repository_pg_test.dart` with two mismatch cases: same
  `source_event_key` but different `event_type`, and different `actor_user_id` → both must throw.
- **Verify:** `dart test --tags pg` green (including the three above); `dart test --exclude-tags pg`
  green.

### 9.5 Step 5 — Delete pre-real-user legacy receipts (migration m0126)

> Precondition: Step 3 merged and baked (no legacy creation path exists). Confirm the "no real
> users" gate still holds before running.

Preflight (record the number in the PR description):
```bash
docker exec postgres psql -U postgres -d postgres -c \
 "SELECT count(*) FROM notification_outbox WHERE access_policy='legacy';"
```
Create `m0126.dart` (register per §9.0):
```dart
part of '_migrations.dart';

/// One-time reset: delete pre-real-user legacy receipts. Tentura has no real
/// users; these carry no compatibility obligation. Not a behavioral no-op.
final m0126 = Migration('0126', [
  r'''DELETE FROM public.notification_outbox WHERE access_policy = 'legacy';''',
]);
```
- **Verify:** after applying, the preflight query returns `0`; feed/markers/email pg tests green.

### 9.6 Step 6 — Contract the shape (migration m0127) — NOT independently revertible

> This DDL makes an old server binary unable to insert receipts (it would omit now-required
> columns / rely on the dropped default). Treat merge+deploy of this step as the **reversible →
> forward-fix-only** boundary; state that explicitly in the PR.

Production preflight — **all must return 0** or STOP:
```sql
SELECT count(*) FROM notification_outbox WHERE access_policy='legacy';
SELECT count(*) FROM notification_outbox WHERE source_event_key IS NULL;
SELECT count(*) FROM notification_outbox WHERE destination_kind IS NULL;
SELECT count(*) FROM notification_outbox WHERE presentation_key IS NULL;
```
Create `m0127.dart` (register per §9.0):
```dart
part of '_migrations.dart';

/// Close the legacy/new receipt-shape split after single-creator convergence.
final m0127 = Migration('0127', [
  r'''ALTER TABLE public.notification_outbox ALTER COLUMN access_policy DROP DEFAULT;''',
  r'''ALTER TABLE public.notification_outbox DROP CONSTRAINT notification_outbox__new_shape_chk;''',
  r'''ALTER TABLE public.notification_outbox
        DROP CONSTRAINT notification_outbox__access_policy_chk,
        ADD CONSTRAINT notification_outbox__access_policy_chk
          CHECK (access_policy = ANY (ARRAY['beacon_content','beacon_tombstone','recipient_safe','profile']));''',
  r'''ALTER TABLE public.notification_outbox ALTER COLUMN source_event_key SET NOT NULL;''',
  r'''ALTER TABLE public.notification_outbox ALTER COLUMN destination_kind SET NOT NULL;''',
  r'''ALTER TABLE public.notification_outbox ALTER COLUMN presentation_key SET NOT NULL;''',
]);
```
- **DO NOT** drop any other constraint. The remaining checks (`__beacon_policy_chk`,
  `__recipient_safe_chk`, `__preference_class_chk`, `__suppression_chk`, `__settlement_*_chk`,
  `__thread_key_chk`) are live domain/security invariants (CR-6).
- **DO NOT** substitute a new `DEFAULT` for `access_policy` — the creator supplies it per event (CR-5).
- **Verify:** preflight all-zero; `dart test --tags pg` green; the realtime multi-client proof
  harness (`reports/realtime-multiclient/updates-*`) green; feed renders unchanged.

### 9.7 Step 7 — Drop dead columns individually (migrations m0128, then a later one)

- `m0128.dart`: `ALTER TABLE public.notification_outbox DROP COLUMN digested_at;` — verified
  0 live refs. First confirm with `grep -rIn "digested_at" packages/server/lib packages/client/lib`
  (excluding `*.g.dart`/migrations) returns nothing.
- `read_at`: **separate, later PR.** Not a simple drop — it lives in the outbox row mapping, the
  domain entity, the m0116 realtime UPDATE trigger's changed-row tuple, and compat tests. First
  produce a dependency inventory (`grep -rIn "read_at\b"`), remove/replace each mapping, update the
  trigger, then drop the column. Gate on mixed-binary compatibility.
- **Leave `dedup_key` and `collapse_key`** — not redundant (CR-10); do not touch without a separate
  approved identity/replay/collapse/retention design.
- **Verify (each drop):** its own migration + a test proving no resolver/digest/trigger reads the
  column; full suites green.

### 9.8 Definition of done

All of: Steps 1–7 merged in order; `dart analyze` clean; `dart test --exclude-tags pg` and
`dart test --tags pg` green; the Step-2 architecture guard test green; the realtime multi-client
proof green; `notification_outbox` has no `access_policy='legacy'` rows, no `__new_shape_chk`, and
`source_event_key/destination_kind/presentation_key` are `NOT NULL`; `userDelete` and retention pg
tests green.

---

## Appendix A — Critical review 2026-07-24 (resolution log)

The full review is retained below for audit. Every blocker is now reflected in §1–§7; the mapping:

- **CR-1 / CR-2** (legacy services are dead surfaces; `record()` needs a caller-owned txn) → old
  Stage 1 removed; §1 rewritten; **Step 2** now proves-dead-and-deletes and preserves
  `handOffChannels`; §3 forbids a second `record()` caller.
- **CR-3** (delete pre-real-user rows) → **Step 5**, with the no-real-users gate retained.
- **CR-4** (m0121 blocks account deletion / retention; throttle table omitted) → throttle added to
  §1; **Step 4** made a hard prerequisite with erasure + retention tests.
- **CR-5** (no safe non-legacy default; not independently revertible) → **Step 6**: `DROP DEFAULT`,
  explicit rollback/mixed-binary gate.
- **CR-6** (only one constraint is split-policing) → §2, Step 6, §7 corrected; "~6 removed" deleted.
- **CR-7** ("single writer" / "read-only repo" inaccurate) → §2 redefines it as single
  *creator/materializer*; Step 3 keeps/splits the lifecycle port.
- **CR-8** (durability overstated) → §1 + §7 say durable **handoff attempt**, not delivery.
- **CR-9** (idempotency guard incomplete) → **Step 4** idempotency-identity item.
- **CR-10** (`dedup_key` / `collapse_key` not redundant) → §3 invariant + Step 7 leaves them.
- **CR-11** (`read_at` gate misframed) → Step 7 reframes as trigger/mapping cleanup.
- **CR-12** (instrumentation misses collapses) → §5 metric by call site + static test.
- **CR-13** (byte-stable test brittle) → §5 semantic fixture + client fixture.
- **CR-14** (needs authoritative T-20 decision) → **Step 1**.

The original full review text (CR-1 … CR-14, including verdict, blockers, high-impact corrections,
and the required corrected sequence) is preserved in this file's git history at the commit prior to
this rewrite; the mapping above is the authoritative record of how each item was addressed.

# ADR 0011: Durable attention topology (T-20 accepted)

## Status

Accepted (2026-07-24). Supersedes the “deferred topology” section of
[ADR-0010](0010-attention-receipt-extension.md) for T-20. V1 receipt-extension
decisions in ADR-0010 (D-1…D-8, feed/badge contract, event taxonomy) remain
normative for readers.

## Context

ADR-0010 recorded the long-term shape
`semantic occurrence → per-recipient receipt → durable delivery job` as
**deferred to T-20**, with v1 using only an extended `notification_outbox`.
That topology is now live. Local evidence (environment: local docker Postgres,
timestamp: 2026-07-24) showed non-empty rows in all five tables; production
rollout gates must re-label counts by environment + timestamp before they
count.

The convergence plan
[`docs/notification-attention-convergence-plan.md`](../notification-attention-convergence-plan.md)
finishes the migration: one receipt creator/materializer, lifecycle
correctness, then schema contraction. This ADR records the accepted T-20
topology and operational contracts so ADR-0010 no longer claims the durable
tables are out of v1 / deferred.

## Decision

### Five-table topology

| Table | Role |
|-------|------|
| `attention_occurrence` | Append-only event; idempotent on `source_event_key` |
| `attention_occurrence_recipient` | Per-occurrence audience snapshot (immutable facts) |
| `attention_channel_delivery` | Job ledger for durable **handoff attempt** (lease + dead-letter) |
| `attention_channel_throttle` | Per-account/channel lease |
| `notification_outbox` | Read model for feed, badges, email digest / immediate email |

### Single receipt creator

Domain use cases build `AttentionDispatchIntent`s and call
`AttentionTransaction.record()` inside their own mutation transaction (via
`TransactionalAttentionCase`). That path materializes occurrence → recipient
snapshot → `notification_outbox` receipt → channel-delivery job. Acknowledgement,
Chat-watermark bridging, settlement, email/digest bookkeeping, collapse, and
retention may still mutate `notification_outbox`; they are not a second
creator.

### Handoff-job guarantee (not provider acceptance)

`attention_channel_delivery` durably retries the channel **handoff attempt**
(lease + dead-letter). A completed / dead job does **not** prove provider
acceptance or end-to-end push/email delivery. Post-commit
`BeaconNotificationPort.handOffChannels()` remains the live channel adapter.

### Idempotency identity

At the occurrence grain, idempotency equality is:

`{source_event_key, event_type, actor_user_id, immutable_payload}`

A reused `source_event_key` whose other equality facts differ is a producer bug
and must throw (not silently no-op). Audience snapshot facts
(recipient ids/reasons/role-facts/collapse-keys/eligibility) are recorded on
first insert only; they are not part of the occurrence-grain equality check
once the occurrence row exists.

### Retention

Settled (`seen_at IS NOT NULL`) outbox receipts older than the retention age
are deleted by the lifecycle worker. Delivery jobs referencing a receipt must
cascade (or be deleted first) so the sweep does not abort on
`ON DELETE RESTRICT`. Occurrence rows are retained history and are not
bulk-deleted by retention.

### Account erasure

Deleting a user must remove account-scoped attention rows in an FK-safe order
(or via `ON DELETE CASCADE` on those account FKs): throttle → delivery →
outbox receipt → occurrence-recipient snapshot. Occurrence rows that other
accounts still reference stay; orphaned occurrences without remaining
recipients are outside the per-user cascade and remain RESTRICT history.

### Operational ownership

| Concern | Owner |
|---------|--------|
| Pending / leased / dead `attention_channel_delivery` jobs | Server task worker (`AttentionChannelDeliveryCase`) |
| `attention_channel_throttle` leases | Same delivery drain path |
| Email digest / immediate email / retention on outbox | `NotificationOutboxRepository` lifecycle methods + digest/task workers |
| Feed / markers / settle GraphQL | Attention resolvers over `visible_attention_receipts` |
| Realtime | Existing `notify_notification_outbox_*` triggers → fail-open
  `emit_realtime_entity_change('notification', …)` |

## Consequences

- ADR-0010’s claim that occurrence / audience / durable-delivery tables are
  deferred for v1 is obsolete; this ADR is authoritative for topology.
- Schema contraction (drop legacy shape / dead columns) is gated by the
  convergence plan Steps 5–7 and must not drop live feed fallback columns
  (`title`/`body`/`action_url`/`category`/`kind`/`priority`).
- Channel delivery remains a durable **handoff** guarantee, not an upgrade to
  provider-accepted delivery.

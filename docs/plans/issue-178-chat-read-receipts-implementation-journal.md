# Journal — issue-178 chat read receipts

Implementation journal for issue #178 (chat read receipts). The parent plan
text predates this journal's addition to git; entries below cite the plan's
bead units by id.

## P1.6 — `bridge_attention_room_seen` UPDATE plan: measure, then decide

**Decision: the index was added.** `notification_outbox__room_message_unseen`
now lives in `m0196` (the same unshipped migration as the `room_seen_peer`
fan-out):

```sql
CREATE INDEX notification_outbox__room_message_unseen
  ON public.notification_outbox USING btree (account_id, beacon_id)
  WHERE destination_kind = 'beacon_room_message' AND seen_at IS NULL;
```

### What was measured

Every `beacon_room_seen` watermark advance fires
`beacon_room_seen_attention_bridge` → `bridge_attention_room_seen()`, whose
UPDATE selects `notification_outbox` rows by `account_id`, `beacon_id`,
`coordination_item_id IS NOT DISTINCT FROM NULL` (General),
`destination_kind = 'beacon_room_message'`, `seen_at IS NULL`, plus an EXISTS
join to `beacon_room_message`.

Per plan §P1.6 the plan was measured with `EXPLAIN (COSTS OFF)` under
`SET enable_seqscan = off` against ~200-row fixtures in two shapes
(`bridge_attention_room_seen_update_plan_pg_test.dart`):

- **obligation-heavy author** — 180 live-obligation noise rows
  (`requires_action = true`, other beacons) + 20 unseen room-message receipts
  on the target beacon;
- **optional-only helper** — 180 optional noise rows
  (`requires_action = false`, other beacons) + 20 unseen room-message
  receipts on the target beacon.

### Measured plan (before the index)

Both shapes produced the same plan — a bitmap scan on the account-wide feed
index, filtering `beacon_id`, `destination_kind`, and `seen_at` post-scan
(~200 rows scanned to reach 20):

```
Update on notification_outbox n
  ->  Nested Loop
        Join Filter: (n.target_entity_id = message.id)
        ->  Bitmap Heap Scan on notification_outbox n
              Recheck Cond: (account_id = '<account>'::text)
              Filter: ((seen_at IS NULL) AND (NOT (coordination_item_id IS DISTINCT FROM NULL::text)) AND (beacon_id = '<beacon>'::text) AND (destination_kind = 'beacon_room_message'::text))
              ->  Bitmap Index Scan on notification_outbox__feed
                    Index Cond: (account_id = '<account>'::text)
        ->  Index Scan using beacon_room_message_beacon_created_idx on beacon_room_message message
              Index Cond: ((beacon_id = '<beacon>'::text) AND (created_at <= '<watermark>'::timestamp with time zone))
              Filter: (NOT (thread_item_id IS DISTINCT FROM NULL::text))
```

### Why the existing indexes did not suffice

- `notification_outbox__unread (account_id, created_at DESC, id DESC) WHERE
  seen_at IS NULL` — no `beacon_id` column, so it cannot select the
  per-beacon slice.
- `notification_outbox__live_obligation_beacon (account_id, beacon_id) WHERE
  requires_action AND settlement_kind IS NULL AND beacon_id IS NOT NULL` —
  room-message receipts are optional (`requires_action = false`), so they are
  outside the predicate.
- `notification_outbox__active_optional_beacon (account_id, beacon_id) WHERE
  NOT requires_action AND cleared_at IS NULL AND beacon_id IS NOT NULL` —
  predicate matches, but it is not selective on `seen_at`/`destination_kind`
  and the planner did not pick it for either shape.

Neither shape used an index selective for the
`(account_id, beacon_id)`-unseen-room-message pattern, which is the bead's
P1.6 criterion for adding the index.

### Verification

`bridge_attention_room_seen_update_plan_pg_test.dart` asserts both fixture
shapes produce no `Seq Scan on notification_outbox` and use
`notification_outbox__room_message_unseen` under `enable_seqscan = off`.

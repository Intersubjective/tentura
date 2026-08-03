# User blocking

**Product:** Blocking is a symmetric, viewer-scoped hide: neither person sees the other on discovery surfaces (feed, graph, search, invite genealogy, mutual friends), and cross-pair writes are rejected at the entry point. There is no push or in-app announcement when someone blocks you — but discoverability is accepted (see design rationale in [`../plans/user-block-design.md`](../plans/user-block-design.md)). Three mechanisms ship together:

| Mechanism | What the user experiences |
|-----------|---------------------------|
| **B1 — direct block** | Hide one person you chose explicitly. |
| **B2 — cascade** | Optionally also hide people they invited (invite-genealogy subtree), with standing-aware filters so independently trusted invitees are not treated as puppets. |
| **B3 — withdrawal** | Your published trust edge toward that person goes to zero while the block stands; underlying evidence is untouched and restores on unblock. Stated in the block sheet as a consequence, not a separate toggle. |

Manage blocks from a profile (**Block**) or **Settings → Blocked users**. Inherited rows can be promoted to a direct block or released via **Unblock** / **Unhide** (v1 releases the whole cascade under that origin — see implementation spec §8.4).

## Engineering

Blocking is enforced through one SQL predicate, `block_hides(viewer, peer)`, defined in migration **`m0135`**. It is true when either direction has a row in `user_block` (the materialized **effective set**). Declared user intent (cascade mode, job status) lives separately in `user_block_intent`.

| Table | Role |
|-------|------|
| `user_block` | Direct and inherited materialized rows `(blocker_id, blocked_id, origin_id)`. Direct: `origin_id = blocked_id`. Inherited: `origin_id` is the cascade root. |
| `user_block_intent` | One row per direct block: `cascade_mode`, `cascade_status`, snapshot/cursor for the background job. |

**`block_hides()` wiring** (all in **`m0136`** unless noted):

| Surface | Mechanism |
|---------|-----------|
| Request feed / room access | `beacon_can_read_content` — `block_hides` is the **first** `WHEN` clause (before steward/participant/help-offer branches). |
| Trust graph neighborhood | `graph()` — drops edges where either endpoint is hidden from the viewer. |
| Chord edges in shared graph | `graph_edges_between(node_ids, positive_only, hasura_session)` — see [Graph visibility](#graph-visibility) below. |
| Mutual friends | `mutual_friends()` — empty when Alice↔Bob blocked; per-result rows filtered. |
| User search / profile | `user_hidden_for_viewer` computed field + Hasura `hidden_for_viewer: {_eq: false}` filter. |
| Presence | `user_presence_hidden_for_viewer` — same pattern. |
| Invite genealogy | Dart: `InviteGenealogyRepository` anonymizes blocked user ids (placeholder nodes; subtree structure preserved). |
| Attention recipients | `AttentionIntentCase` filters before snapshot write. |
| Forwards, help offers, contacts, invites, room messages, coordination assignment | Server use-case guards via `UserBlockRepositoryPort` (`isBlockedPair` / `hiddenPeerIds`). |

Signup under a blocked ancestor inherits rows via trigger `user_block_inherit_on_invite` (**`m0136`**).

**Withdrawal (B3)** — migration **`m0137`**: `trust_rebuild_effective_edge` gates the value published to MeritRank to `0` when `user_block` contains `(subject=blocker, object=blocked)`. `user_trust_source_edge` and `s_*` are never written by blocking; `prev_sent_weight` tracks what was last published. Block/unblock/cascade/release call rebuild with epsilon override `-1`.

**Server API:** V2 GraphQL `userBlock` / `userUnblock` / `userBlockPromote`, `myBlocks`, `blockInherited`, `blockPreview` (blocker id from JWT only). **Client:** `packages/client/lib/features/block/`.

### Cascade materialization

When `cascade_mode > 0`, a background job (`BlockCascadeCase` in `TaskWorkerCase`) walks `block_cascade_candidates()` from **`m0135`**, inserts inherited `user_block` rows in batches, applies withdrawal per new row, and runs a catch-up pass for signups after the snapshot. Depth/row caps set `cascade_status = 3` (capped). Mode-1 **release sweep** (`BlockReleaseSweepCase`) periodically deletes inherited rows whose members later earn independent standing (`block_cascade_unattached` flips false); direct rows are never released by the sweep.

### Direct-block cleanup

`UserBlockCase` withdraws pending help offers, cancels uncancelled forward edges, and deletes contact rows for **direct** blocks only — not for inherited rows.

## Config (server env)

| Variable | Default | Meaning |
|----------|---------|---------|
| `BLOCK_RATE_LIMIT_PER_DAY` | `50` | Max block intents per blocker per rolling 24h |
| `BLOCK_CASCADE_MAX_DEPTH` | `6` | Max invite-tree depth for cascade candidate query |
| `BLOCK_CASCADE_MAX_ROWS` | `5000` | Max inherited rows materialized per intent |
| `BLOCK_CASCADE_BATCH_SIZE` | `500` | Rows inserted per materialization batch |
| `BLOCK_RELEASE_SWEEP_INTERVAL` | `6h` | Throttle for mode-1 probation release sweep |

Cascade materialization is throttled (~1 minute) in `TaskWorkerCase`; release sweep uses `trustSweepBatchSize` / `trustSweepTimeBudget` from the trust maintenance knobs.

## Migrations

| Migration | Contents |
|-----------|----------|
| **`m0135`** | `user_block`, `user_block_intent`, `block_hides`, `block_cascade_unattached`, `block_cascade_candidates` |
| **`m0136`** | `beacon_can_read_content` wall, `graph` / `graph_edges_between` / `mutual_friends` filters, `user_hidden_for_viewer`, `user_presence_hidden_for_viewer`, `user_block_inherit_on_invite` trigger |
| **`m0137`** | Withdrawal gate inside `trust_rebuild_effective_edge` |

Deeper design and test matrix: [`../plans/user-block-design.md`](../plans/user-block-design.md), [`../plans/user-block-implementation-spec.md`](../plans/user-block-implementation-spec.md).

## Known limitations

These are **accepted v1 behavior**, not bugs. Adversarial tests pin them in `packages/server/test/data/repository/user_block_adversarial_pg_test.dart`.

### X1 — Invite laundering

Cascade follows the **invite genealogy tree**, not social intent. If B is cascade-blocked, a new account invited by an **unblocked** friend F (instead of B) does **not** inherit the block. Mitigation is social/upward (design §10.6), not technical — out of scope for this feature.

### X15 — Re-registration

Blocks are **identity-scoped** (account id), not person-scoped. A fresh account id is never caught by a prior block on a deleted or abandoned identity.

### X16 — Steward blindness

`block_hides` is evaluated **before** steward and participant branches in `beacon_can_read_content`. A steward who blocks a request's author loses visibility of that request too, despite their steward role. This is intentional filter ordering, not data loss.

### Open commitment eject gap (spec §7.4)

**Direct blocks:** `blockPreview.openCommitmentCount` warns before confirm; proceeding ejects the blocked party from request chat access (pinned by adversarial test X13 direct).

**Inherited (cascade) blocks — v1 gap:** The design called for an exception so cascade-only blocks would **not** eject someone from a request with an open commitment (they were never shown a per-person warning). That SQL exception was **never built** — `beacon_can_read_content` uses unconditional `block_hides`, so inherited blocks eject exactly like direct blocks today. Adversarial test **X13 inherited** pins this actual behavior. Shipping without the exception is explicitly sanctioned in spec §7.4; this doc records the gap versus original intent.

## Graph visibility

`graph_edges_between` takes a third argument `hasura_session json` (Hasura injects it from the JWT). For edges whose **both** endpoints lie in the supplied `node_ids` set, the function returns a row only when **neither** endpoint is hidden from the viewer:

```sql
AND NOT public.block_hides(hasura_session ->> 'x-hasura-user-id', e.subject)
AND NOT public.block_hides(hasura_session ->> 'x-hasura-user-id', e.object)
```

**Consequence:** chords drawn between people already on screen can disappear when **either** endpoint is blocked by the viewer — including an edge between two **other** people who are both adjacent to someone on the viewer's block list. This is broader than hiding only edges that touch the viewer directly. Neighborhood view `graph()` applies the same predicate to both endpoints of each `mr_graph` edge.

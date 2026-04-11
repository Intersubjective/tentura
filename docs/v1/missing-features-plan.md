# V1 missing features — implementation plan (overview)

Reference: feedless coordination, inbox-first, manual forwarding, MR-guided visibility. **Canonical locks:** `[product-decisions.md](./product-decisions.md)`.

**Execution is for follow-up agents.** Remaining open questions are minor unless marked.

**Recently implemented:** §2 (inbox row provenance + lifecycle badge), §4 (`beacon.state` lifecycle, My Work Active/Closed, client no longer uses `enabled` on `BeaconModel`), and §3 forward screen (header, filters, MR-sorted sectioned list, involvement-driven buckets, shared + per-recipient notes, `computeBeaconListSections` single-pass UI data). See those sections for details and ops follow-ups.

**Overcommit coordination (active beacon):** design and implementation map — [`../overcommit-coordination-feature-design.md`](../overcommit-coordination-feature-design.md) (commit note + optional help-type, author per-commit responses, beacon `coordination_status`, uncommit reasons, Inbox/My Work/detail UI).

---

## 1. Inbox: sort (MR / Recent / Deadline)

**Brief:** Sort switch on inbox: MR, Recent, Deadline.

**Decision (see `product-decisions.md`):** **MR** = **server-computed per-beacon MeritRank score** for current user + context. Client sends sort mode; server orders or returns comparable field.

**Current behavior**

- `packages/client/lib/features/inbox/ui/screen/inbox_screen.dart` — sort UI exists (choice chips): Recent / MeritRank / Deadline.
- `packages/client/lib/features/inbox/ui/bloc/inbox_state.dart` — sorting is **client-side**:
  - Recent: `latestForwardAt` desc
  - MeritRank: `beacon.score` desc (from `BeaconModel.scores.dst_score`)
  - Deadline: `beacon.endAt` asc (nulls last)
- `packages/client/lib/features/inbox/data/gql/inbox_fetch.graphql` — query still requests `order_by: { latest_forward_at: desc }` only (server-side), then client re-sorts per tab.

**Likely work**

- **Server:** Column or view field for MR score per beacon per viewer; support `order_by` variants for MR / recent / deadline (nulls last for missing deadline).
- **Client:** `InboxState` sort enum, UI control, query variables, Ferry regen.

**Open (minor)**

- “Recent” default: last forward vs last beacon update — pick one and document in API.

---

## 2. Inbox row: forward senders + stronger provenance

**Brief:** Forward count, **who forwarded** (top senders), note preview, **status badge**, compact author/context line.

**Status:** **Implemented** (client + DB function). **Ops:** register Hasura computed field so `inbox_provenance_data` is non-null in production — see `[packages/server/WORKAROUNDS.md](../../packages/server/WORKAROUNDS.md)` §4.

**Implemented behavior**

- **Server (m0015):** `public.inbox_item_inbox_provenance_data(inbox_row, hasura_session)` returns JSON text: MR-ranked top senders (via `mr_mutual_scores` + `beacon_forward_edge`), per-sender `id` / `title` / `mr` / `imageId`, `totalDistinctSenders`, `strongestNotePreview` (note from highest-MR sender among distinct forwarders, trimmed to 200 chars). Respects `recipient_rejected` and inbox/beacon context alignment.
- **Client:** `inbox_fetch.graphql` selects `inbox_provenance_data`; `InboxProvenance` / `inbox_item.dart` / `inbox_repository.dart`; `inbox_item_tile.dart` — lifecycle **badge** from nested `beacon.state` → `BeaconLifecycle`, up to **3** `AvatarRated` senders + **+N** overflow, note from provenance when present else `latest_note_preview`, **author + context** line under title.
- **Heuristic (locked):** strongest note = from top-MR sender; max avatars **3 + overflow count**.

**Remaining (optional / follow-up)**

- Automated tests for provenance JSON shape and ranking edge cases (plan § validation).
- If Hasura introspection type for the computed field differs from `String`, adjust `schema.graphql` + Ferry after reload.

---

## 3. Forward screen: full brief UX

**Brief:** Beacon summary header; filters; sort; grouped sections; reachability hints; sticky bar; optional per-recipient notes.

**Decision:** **Client-side filters** on candidates plus **beacon involvement** (forwarded, unseen, already involved including committed/withdrawn/declined, author). See `product-decisions.md`.

**Status:** **Largely implemented** (client + server involvement inputs + forward mutation with per-recipient notes). **Still open:** `parentEdgeId` not passed from cubit; route presentation (`fullscreenDialog: true` on `ForwardBeaconRoute` — align with §7 / contradictions plan).

**Implemented behavior**

- **Client data:** `beacon_involvement_data.graphql` (V2 `beaconInvolvement`) + `ForwardRepository.fetchBeaconInvolvement` supplies beacon, author, `forwardedToIds`, `committedIds`, `withdrawnIds`, `rejectedIds` (declined), **`myForwardedRecipients`** (per-sender dedup); merged with friends list into `ForwardCandidate` + `CandidateInvolvement`.
- **UI:** `BeaconForwardHeader`, `ForwardFilterBar` (All / Best next / Unseen / Already involved), search field, `ForwardCandidateTile` with involvement copy; bottom bar: shared note, `PerRecipientNotesPanel`, forward CTA.
- **Sections (All):** **Recommended** (reachable, `canForwardTo` — includes `unseen`, `forwarded` by others, and `watching`), **Others** (reachable, not selectable — `forwardedByMe`, `committed`, `withdrawn`), **Cannot forward** (author + declined, reachable), **Not reachable** — MR sort within each bucket via `ForwardState.computeBeaconListSections()` (single search pass + one sort per bucket; avoids repeated getter work).
- **Per-sender forward dedup:** A user can forward a beacon to someone who already received it from a different sender, but **not** to someone they personally already forwarded to. `CandidateInvolvement.forwardedByMe` blocks re-selection and shows the note from the previous forward. Server `BeaconInvolvement.myForwardedRecipients` returns `{recipientId, note}` pairs filtered to the current user's edges.
- **Mutation:** `forward_beacon.graphql` / `beaconForward` with `perRecipientNotes` map.

**Remaining**

- **Product + client:** Wire `**parentEdgeId`** from the forward context (edge / branch rule) when chain semantics are finalized; repository API already accepts it.
- **Shell:** Consider normal push vs fullscreen dialog when global AppBar work (§7) lands.

---

## 4. My Work: Active vs Closed + beacon state enum

**Brief:** Active / Closed sections; inside Active: All / Authored / Committed.

**Decision:** Replace `**enabled`** with **lifecycle** driven by `**beacon.state`** (`OPEN`, `CLOSED`, `DELETED`, `DRAFT`, `PENDING_REVIEW` as smallints 0–4). **Active** = `OPEN` / `DRAFT` / `PENDING_REVIEW`; **Closed** = `CLOSED` / `DELETED`.

**Status:** **Implemented** (stack: m0015 backfill + CHECK + trigger; client domain + queries + UI).

**Implemented behavior**

- **Server (m0015 + m0016):** m0015 backfilled `beacon.state` from legacy `enabled` while preserving `state = 2` (deleted); `CHECK (state >= 0 AND state <= 4)`; a temporary trigger synced `**enabled`** until **m0016** dropped `**enabled`** and that trigger entirely.
- **Client domain:** `BeaconLifecycle` (`beacon_lifecycle.dart`), `Beacon.lifecycle`, `isListed`; `BeaconModel` / `beacon_model.graphql` use `**state`**, not `enabled`.
- **Mutations:** `beacon_update_by_id.graphql` sets `**state`**; `BeaconRepository.setBeaconLifecycle`; profile beacon list (`beacons_fetch_by_user_id.graphql`) and `**my_field_fetch.graphql**` filter by `**state**`; mine / view controls toggle **OPEN ↔ CLOSED** (not deleted).
- **My Work:** Four queries in `my_work_fetch.graphql` — `MyWorkAuthoredActive` / `MyWorkAuthoredClosed` / `MyWorkCommittedActive` / `MyWorkCommittedClosed` with `state` filters; `MyWorkSection` + chips on `my_work_screen.dart`; cubit fetches all four lists; beacon repo events trigger **refetch** on update.

**Remaining (optional / follow-up)**

- ~~Drop `**enabled`** from Postgres / Hasura~~ — done (migration **m0016** drops column + sync trigger; Hasura permissions updated).
- Product tweak if **PENDING_REVIEW** should appear under Closed instead of Active.

---

## 5. Network: Contacts / Reachable / Graph

**Brief:** Operational sections; **chat remains** per `product-decisions.md`.

**Current behavior**

- `friends_screen.dart` — Friends + Invitations; `ChatPeerListTile`.

**Likely work**

- Add **IA** for Contacts / Reachable / Graph **without removing** 1-to-1 chat (secondary actions, subtabs, or overflow menu — design choice).

---

## 6. Me: Availability, Capabilities, Settings

**Brief:** Me — Availability, Capabilities, Settings.

**Decision:** **Keep** personal beacon list on profile for now (`profile_body.dart` → `BeaconScreen`).

**Current behavior**

- `profile_screen.dart` / `profile_body.dart` — no Availability/Capabilities editors.

**Likely work**

- New sections + server fields as needed; optional copy pass on opinions/MR.

**Open**

- Availability/Capabilities shape (text vs tags vs structured).

---

## 7. Global controls: AppBar actions (required)

**Brief:** Context + new beacon + scan everywhere.

**Decision:** **AppBar actions only** for global actions; **refactor shell for consistency** — see `product-decisions.md`.

**Current behavior**

- `ContextDropDown` appears on multiple screens (at least Inbox, My Work, My Field, Rating, Graph), but global actions are not yet unified into a shared AppBar.
- New beacon action lives in `profile_body.dart` (profile screen content).
- Scan/connect entry is via Friends screen FAB (connect bottom sheet).

**Likely work**

- **Client:** Shared `AppBar` for `AutoTabsScaffold` children (or wrapper widget): context menu, `IconButton`/toolbar for create + scan; **remove** redundant FABs where replaced; move `ConnectBottomSheet` / QR entry to AppBar action.

---

## 8. Beacon detail: Overview / Timeline / Forward-chain graph

**Brief:** Overview | Timeline | Forward chain graph; Commit / Forward / Hide.

**Current behavior**

- `beacon_view_screen.dart` — Timeline | Commitments; graph via separate `GraphRoute`.

**Likely work**

- Third tab or embedded chain view + optional deep link to full graph.

---

## 9. Hide on beacon detail

**Brief:** Hide as primary action where relevant.

**Likely work**

- Add Hide on `BeaconViewScreen` for non-owners; reuse `InboxRepository.setHidden` or shared use case.

---

## 10. Dead / stub routes

- `updates_screen.dart` / unregistered `UpdatesRoute` — remove or wire intentionally.

---

## Implementation notes: §2 Inbox row + §4 Lifecycle / My Work (code review)

Post-implementation review of the shipped stack (server migrations, Hasura contract, client domain/UI). Use this for deploy checklists and follow-up work—not duplicate product spec.

### What works well

- **Layering:** DB function → JSON text → `InboxProvenance.parse` → `InboxItem` → tile keeps transport concerns out of widgets.
- **MR in SQL:** One `mr_mutual_scores` pass joined to forward senders avoids N+1 or client-side ranking.
- **Lifecycle model:** `BeaconLifecycle` + `Beacon.lifecycle` + `isListed` is clearer than lifecycle via `enabled` alone.
- **My Work queries:** Four explicit GraphQL operations (authored/committed × active/closed) match the product split.
- **Degradation:** Missing `inbox_provenance_data` yields empty senders; note falls back to `latest_note_preview`.
- **JSON robustness:** `mr` parsed as `num` or string where needed for GraphQL/Ferry quirks.

### Risks and gaps

1. **Hasura computed field** — Full inbox row (avatars + MR-ranked note) needs `inbox_item.inbox_provenance_data` registered against `inbox_item_inbox_provenance_data` (`[packages/server/WORKAROUNDS.md](../../packages/server/WORKAROUNDS.md)` §4). Without it, the UI still works but only with fallback note and no forwarder strip.
2. **Backfill vs `state` 3/4** — m0015 `UPDATE beacon SET state = CASE …` preserves `state = 2` (deleted) but otherwise derives from `enabled`. Any rows that already used `DRAFT`/`PENDING_REVIEW` (3/4) before migration would be reset to OPEN/CLOSED—safe only if those values were never persisted pre-migration.
3. ~~`**enabled` / `state` drift**~~ — Resolved: `**enabled`** column removed (m0016); `**state**` is the only lifecycle column.
4. **Mine menu = OPEN ↔ CLOSED only** — Author toggle does not drive `DRAFT`, `PENDING_REVIEW`, or `DELETED`. Closing from `DRAFT`/`PENDING_REVIEW` becomes `CLOSED` (by design for V1; document for support).
5. **Unknown `state`** — Client `BeaconLifecycle.fromSmallint` maps out-of-range values to `**open**`, which can mis-label data if the CHECK constraint is bypassed or schema drifts.
6. **My Work refresh cost** — `RepositoryEventUpdate<Beacon>` triggers a full four-query `**fetch()`**; correct but chatty if many updates arrive in succession.
7. **Inbox header density** — First row combines forward count, lifecycle chip, date, and overflow menu; very narrow widths or long translations may clip (chip is not `Flexible`).
8. **Tests** — Plan validation called for migration/provenance/My Work tests; **not added** in the initial delivery—treat as explicit debt.

### Minor / style

- `InboxProvenance.parse` as a static method may trigger analyzer “prefer constructor” info; optional cleanup.
- `Beacon.rejectedUserIds` remains on the entity but is not populated from the shared `BeaconModel` fragment (forward flow uses a separate fetch); no functional bug, slightly confusing for readers.

### Follow-ups (recommended)

- Register and verify Hasura metadata in each environment; re-introspect `schema.graphql` if the computed field’s GraphQL type differs from `String`.
- Add focused tests: provenance JSON shape, tie-breaking for MR, My Work section membership by `state`.
- If `DRAFT`/`PENDING_REVIEW` are ever written pre-migration, document or adjust backfill order.
- Consider batching or debouncing My Work refetch on beacon stream noise if it becomes observable in production.

---

## 11. Watching (passive inbox stance)

**Brief:** Triaged passive follow — not Inbox pending, not My Work ownership; visible to upstream forwarders on the forward screen. See [`watching-mechanism.md`](./watching-mechanism.md) and [`product-decisions.md`](./product-decisions.md) (Watching).

**Status:** **Done** (Phase 1 scope) — auto-watch on forward, involvement fields, copy/UX, beacon detail action, uncommit → watching on server.

**Implemented / baseline**

- DB: `inbox_item.status` (`0` needs_me, `1` watching, `2` rejected).
- Client: Inbox tabs (Needs me / Watching / Rejected); overflow move to watching on Needs me; `InboxRepository.setStatus` via Hasura.

**Shipped**

- Server: `beaconForward` transaction sets sender to watching when no active commitment; V2 `beaconInvolvement` includes `watchingIds` and `onwardForwarderIds`; `beaconWithdraw` upserts sender watching.
- Client: `CandidateInvolvement.watching`, precedence in `forward_cubit`, forward tiles + l10n, neutral Watching chip on inbox, “Move to Watching” / “Return to Needs me” copy, beacon detail action + `InboxItemStatusForBeacon` query, inbox silent refresh after forward and after local `setStatus`.

---

## Summary


| #   | Feature                           | Status           | Main touchpoints                                                                                                                                                                                                                                                                         |
| --- | --------------------------------- | ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Inbox sort (MR server)            | Open             | `inbox_fetch.graphql`, inbox cubit/UI, server MR field                                                                                                                                                                                                                                   |
| 2   | Inbox row                         | **Done**         | `inbox_fetch.graphql`, `inbox_provenance.dart`, `inbox_item_tile.dart`, m0015 + Hasura (WORKAROUNDS §4)                                                                                                                                                                                  |
| 3   | Forward UX + involvement          | **Largely done** | `beacon_involvement_data.graphql` (V2), `forward_beacon.graphql`, `forward_repository.dart`, `forward_cubit.dart`, `forward_state.dart` (`computeBeaconListSections`), `forward_beacon_screen.dart`, widgets under `forward/ui/widget/`; **open:** `parentEdgeId` in cubit, route shell (§7) |
| 4   | Lifecycle + My Work Active/Closed | **Done**         | m0015, `beacon_lifecycle.dart`, `beacon_model.graphql`, `my_work_fetch.graphql`, `my_work_`*, `beacon_repository`, beacon mine/view controls                                                                                                                                             |
| 5   | Network IA + chat                 | Open             | `friends_screen.dart`                                                                                                                                                                                                                                                                    |
| 6   | Me sections                       | Open             | profile, server                                                                                                                                                                                                                                                                          |
| 7   | AppBar shell                      | Open             | `home_screen.dart`, tab screens, router                                                                                                                                                                                                                                                  |
| 8   | Beacon graph tab                  | Open             | `beacon_view_screen.dart`                                                                                                                                                                                                                                                                |
| 9   | Hide                              | Open             | `beacon_view_screen.dart`                                                                                                                                                                                                                                                                |
| 10  | Updates cleanup                   | Open             | router, `features/updates`                                                                                                                                                                                                                                                               |
| 11  | Watching                          | **Done**         | `watching-mechanism.md`, `forward_case.dart`, `commitment_case.dart`, `beacon_involvement_case.dart`, `beacon_involvement_data.graphql`, `inbox_item_status_for_beacon.graphql`, `forward_cubit.dart`, `inbox_item_tile.dart`, `beacon_view_screen.dart`                                  |



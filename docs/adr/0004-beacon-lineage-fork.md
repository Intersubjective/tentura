# ADR 0004: Beacon lineage via a server-side fork mutation with fully-derived subjective forwarding memory

Status: Accepted (2026-06-13); amended (2026-06-13) after multi-model plan review — see "Amendments" below.

## Context

Tentura needs to support repeated practices (a new occurrence of a similar past event) without introducing recurring beacons, subscriptions, series/channel pages, or author-defined beacon categories. The chosen mechanism is **lineage**: a new beacon is created from a previously visible beacon, recording `lineage_parent_beacon_id` (immediate source) and `lineage_root_beacon_id` (ultimate ancestor) on the beacon row.

A forking user should also get **forwarding suggestions** for the new draft, drawn only from that user's own visible memory across the lineage (their own forwards, positive reviews, private person-tags, and downstream help they routed). This must preserve Tentura subjectivity: the same forked beacon must yield different suggestions for different users, and there must be no global "best candidates" list.

Two questions drove this ADR:

1. **Where does the fork happen** — a server-side mutation, or client-side prefill of the create screen followed by the existing `beaconCreate`?
2. **Where does the subjective memory live** — derived on read, or persisted somewhere?

## Decision

1. **Server-side `beaconFork` mutation.** A single V2 mutation reads the source, copies reusable content, sets the lineage pointers atomically, and returns a new DRAFT (`state = 3`). The client then opens the returned draft in the editor. Rationale: image-blob ownership and (future) server-side concerns belong on the server; lineage pointers are written atomically with creation rather than via a follow-up patch; and there is one clean audit point. **(Amended)** Visibility is **not** enforced by `getBeaconById(filterByUserId:)` — that filter is author-only. See Amendment A.

2. **Copy policy (reusable content only).** Copy `title`, `description`, `need_summary`, `success_criteria`, `needs`, `tags`, `icon_code`, `icon_background`, `context`, and coordinates. Do **not** copy `start_at`/`end_at` (a fork is a new occurrence). **Duplicate image blobs** (new image rows owned by the forker) **only when the forking user is the source author**; non-author forks copy no images (the image-ownership model ties blobs to the author, and a beacon delete removes its blobs, so sharing `image_id` across beacons would be fragile). Never copy committers, participants, room/chat, activity, reviews, forwarding recipients, read/unread state, closure state, or private data unavailable to the forking user.

3. **Forkable = any visible beacon except DELETED.** Including the user's own beacons and own drafts. **(Amended)** The gate is: load the source by id **without** the author filter, reject `DELETED`, and reject another user's `DRAFT` (drafts are author-only). See Amendment A.

4. **Subjective forwarding memory is fully derived, never persisted.** A V2 query `beaconLineageForwardSuggestions(id)` computes per `(current_user_id, beacon_id, lineage_parent_beacon_id)` from existing rows only: `beacon_forward_edge` (this user's notes/recipients/`recipient_rejected`/`parent_edge_id` chains), `beacon_evaluation` (this user's positive reviews), and `person_capability_event` (this user's private labels). Nothing new is stored on the beacon row; the "copied forward text" is returned as a derived `suggestedNote`. This guarantees subjectivity by construction and forbids caching suggestions as an objective beacon property (consistent with ADR 0001's "capability reads are derived via V2 use cases" stance).

5. **Server emits subjective memory only; MeritRank stays client-side.** The query returns user ids + group + reason + auto-select + `suggestedNote`, where group and reason are **stable slugs, never localized text**. The client overlays this onto its existing MeritRank candidate list (group 5), batch-fetches profiles for suggested ids not already present, and applies reachability/visibility suppression client-side. Auto-selection is conservative: only people this user forwarded to who then helped (group 1) or who routed to a downstream help offer (group 3).

6. **Ranking policy lives in a use case, not in SQL.** The server data port returns *facts* (the user's lineage forward edges, positive evaluations, private tags, and boolean "helped"/"routed-to-help" flags) as domain value objects; the server use case classifies facts into groups, dedups, applies the pushback de-prioritize/suppress thresholds, chooses auto-select, and selects the suggested note. This keeps the rules unit-testable without a database and lets them evolve without a migration. Localization and the int->enum mapping are interface-adapter concerns on the client.

7. **Lineage set = the whole tree.** Suggestions draw from the root plus every beacon sharing that root; the per-user subjective filter naturally narrows it. The objective-control preview on a non-fork beacon treats that beacon as its own root. **(Amended)** The narrowing is not automatic for *outcome facts about other people* (`whoHelped`/`whoRoutedToHelp`): those must be scoped to lineage beacons the caller actually touched (own forward edge or author), or the caller could learn outcomes on sibling forks they cannot see. See Amendment B.

8. **Parent reference is a link, not a title.** The child shows a generic clickable "Created from a previous beacon" that navigates to the parent by id; the parent's title is never fetched on the child.

## Consequences

- Lineage pointers persist through DRAFT -> OPEN (publish only changes `state`), so a published fork still shows its parent link and can itself be forked, building the tree.
- Suggestions are inherently per-user and cannot leak another participant's private memory; cold-start forks (no prior memory) simply fall back to the normal MeritRank list.
- A new client cannot be older than the server feature: the fork is additive, so old clients merely lack the action — no `MIN_CLIENT_VERSION` bump.
- The server `beaconFork` write must run inside `withMutatingUser(userId, ...)` so the beacon-invalidation trigger suppresses the echo to the originating user.

## Alternatives considered

- **Client-side prefill + `beaconCreate` with lineage args** — rejected: cannot copy this user's subjective forward note without server work, sets lineage via a non-atomic follow-up, and duplicates the visibility check that the server already owns.
- **Persisting suggestions (per-(user,draft) cache table) or a default forward note on the draft** — rejected: re-introduces the risk of treating subjective memory as an objective beacon property; on-demand compute with short-lived in-memory memoization is cheap (one query) and inherently per-user.
- **Server-side MeritRank/group-5 + embedded profiles** — rejected for now: MeritRank logic and candidate bucketing already live on the client; keeping the server query a pure subjective-memory read mirrors the existing `beaconInvolvement` pattern (returns ids the client resolves).
- **Copying images by sharing `image_id`** — rejected: fragile under the author-owned blob model (source deletion would orphan the fork's images).

## Amendments (2026-06-13, post multi-model review)

- **A. Fork/suggestions visibility gate.** `getBeaconById(filterByUserId:)` is an **author-only** filter (`beacon.userId == @ReferenceName('author')`), not a visibility filter; the original rationale in Decision 1 was wrong. Both `beaconFork` and `beaconLineageForwardSuggestions(id)` load the source by id **without** the author filter, then gate: reject `DELETED (2)`; reject `DRAFT (3)` when `author != caller`. This matches the Hasura `beacon` select permission (`filter: {}`, any authenticated user reads any non-draft beacon). The two entry points share one private gate helper.
- **B. Outcome-fact scoping (subjectivity).** `whoHelped`/`whoRoutedToHelp` are computed only over `lineageBeaconIds ∩ {beacons the caller touched}`, never the whole tree, to avoid revealing outcomes on invisible sibling forks. `whoRoutedToHelp` is the **downstream/descendant** inverse of `fetchHelpOffererPathChain` (a different recursive CTE, cycle-guarded), not a mirror of it.
- **C. Server migration mechanics.** The schema change is a hand-written `migrant` `Migration('0087', [...])` registered in `_migrations.dart`; the server keeps `schemaVersion = 1` and does not use `drift_dev make-migrations`/`onUpgrade`. Self-FKs use `ON DELETE SET NULL` (beacons soft-delete).
- **D. Client profile prerequisite.** `ProfileRepositoryPort` has only `fetchById`; a batch `fetchProfilesByIds` that selects the `scores` relationship (so profiles carry viewer-relative `score`/`isSeeingMe`) is a hard prerequisite for reachability suppression + ordering of off-list suggested users.
- **E. Forward render path.** The lineage block renders above `state.visibleRecipients` in `forward_beacon_screen.dart` independent of the active scope filter; `ForwardState.computeBeaconListSections` is currently unused and is not the render path.

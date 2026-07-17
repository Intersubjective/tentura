---
status: done
kind: plan
---
# Hidden-neighbor counter badges for graph nodes

## Context

In both the relationships graph and the invite genealogy graph, a node's full neighbor set is not loaded up front — the user double-taps a node to progressively reveal more of its neighbors (`GraphCubit.setFocus` → `_fetch()`, `graph_cubit.dart:155-424`). Today there's no visual signal for *how many* neighbors are still hidden, so users can't tell whether a node is a dead end or has 50 more connections worth exploring. This feature adds a small counter badge per node showing the hidden-neighbor count, which decreases (and eventually disappears) as more of that node's neighbors get loaded into the graph.

Both graphs share one rendering stack (`GraphBody` + `GraphCubit` + `GraphNodeWidget`), so the client-side plumbing is shared. The backends differ (Postgres pagination for genealogy vs. a MeritRank-fed `user_trust_edge` table for relationships), but both now reduce to a single well-understood source table each — see the backend sections below.

## Counting semantics

- **Genealogy**: tree structure, tap reveals children only. `hidden = totalChildren - loadedChildren` for that node. Parent edge is always already shown (that's how you navigated there), so no ambiguity.
- **Relationships graph**: `hidden = totalDegree - currentlyConnectedEdgeCount`, where `currentlyConnectedEdgeCount` is derived client-side by counting edges touching that node id in the live `graphController` state.
- Badge is hidden entirely when `hidden <= 0` or when total is unknown (not yet supplied by server for that node).

## Backend: genealogy

`InviteGenealogyRepository.fetchChildren` (`packages/server/lib/data/repository/invite_genealogy_repository.dart:101-175`) runs a cursor-paginated query (`WHERE ancestor_node_key = $1 AND (descendant_user_created_at, descendant_node_key) > ($2, $3) ORDER BY ... LIMIT $4`). A `COUNT(*) OVER (PARTITION BY ancestor_node_key)` added to *that* query would only count rows remaining after the cursor filter, not the true total — wrong. Instead, run total counts as a **separate small aggregate query**, cheap and correct given the existing index `invite_genealogy_ancestor_node_key_children_page(ancestor_node_key, descendant_user_created_at, descendant_node_key)`:

```sql
SELECT ancestor_node_key, COUNT(*) AS total_children
FROM invite_genealogy
WHERE ancestor_node_key = ANY($1)
GROUP BY ancestor_node_key
```

Badges need to appear on nodes the user hasn't tapped yet (so they know which ones are worth tapping), which means counts are needed for more than just the just-tapped ancestor:

1. **Focused ancestor**: whichever node was just tapped — count via the query above with `$1 = [focusNodeKey]`.
2. **Newly returned child nodes**: each page from `fetchChildren` returns child nodes that themselves may have children — batch the same query with `$1 = <all descendant_node_keys just returned>` right after the page fetch, so their badges are populated immediately.
3. **Bootstrap/initial lineage nodes**: whatever node set the first-load query (`invite_genealogy_fetch.graphql`) returns also needs the same batched treatment applied to its node keys.

Expose a repository method like `fetchChildCounts(nodeKeys: List<String>) -> Map<String, int>` used in all three call sites, rather than trying to bolt a count onto the paginated query.

## Backend: relationships graph (MeritRank)

The `graph()` SQL wrapper (`packages/server/lib/data/database/migration/m0002.dart:263-287`) delegates to the MeritRank C extension `mr_graph(viewer, focus, context, positive_only, offset, limit)` and returns `SETOF public.mutual_score` (`src, dst, src_score, dst_score`) — no degree/count is available from it.

Beacon/comment vote edges no longer feed MeritRank in the current version: `vote_comment` was dropped in `m0037.dart` (comments replaced by beacon room messages, no `vote_comment` analogue per `m0044.dart`), and `m0061.dart` dropped the triggers that synced `vote_beacon` mutations into MeritRank. Direct user↔user trust is now the only source, written entirely through `trust_apply_evidence`/`meritrank_apply_evidence` (`m0088.dart`) into `user_trust_edge` (`packages/server/lib/data/database/table/user_trust_edges.dart:7`) — confirmed there's no other edge table to union against. This matches the client: the relationships-graph screen constructs `GraphCubit` without an explicit `context` (`graph_screen.dart:29-32`), so `GraphCubit.state.context` defaults to `''` (`graph_cubit.dart:175`) — the same empty context `trust_apply_evidence` always writes with (`mr_put_edge(subject, object, weight, ''::text, 0)`). So a degree count can be a straightforward:

```sql
SELECT COUNT(*) FROM user_trust_edge WHERE subject = $1 OR object = $1
```

`positive_only` filtering only needs the edge's *sign*, not a precise current weight — a hidden-neighbor badge doesn't need to match MeritRank's exact decayed score, just "is this relationship currently positive." `user_trust_edge`'s stored `prev_sent_weight` (the weight last pushed to MeritRank, `m0088.dart:70-100`) already carries that sign and is good enough for this purpose:

```sql
SELECT COUNT(*) FROM user_trust_edge
WHERE (subject = $1 OR object = $1) AND ($2 = false OR prev_sent_weight > 0)
```

No decay recomputation via `trust_edge_weight()` needed — that would only matter if the badge had to match MeritRank's precise live score, which it doesn't.

Surfacing the count still requires changing the Postgres return shape: `mutual_score` (`packages/client/lib/data/gql/schema.graphql:2724`) is a fixed composite type with only `src, dst, src_score, dst_score, user, beacon` — adding a degree field means altering that composite type (or introducing a new one) plus updating Hasura metadata/tracking and regenerating introspection, not just editing a client `.graphql` query file.

## Client cubit & state design

Keep counts **out of `NodeDetails` entirely** — do not add a `totalNeighborCount` field there. `NodeDetails.==`/`hashCode` (`node_details.dart:35-49`) already deliberately excludes some fields (e.g. `rScore`, `isHelpOfferer`) from equality, and `ValueKey(node)` in both `nodeBuilder` and `labelBuilder` (`graph_body.dart:203`) relies on that equality — a field that changes over time but isn't part of equality won't produce a new key/rebuild, while including it risks spurious key changes and duplicate controller entries. Simpler and safer: keep counts purely in `GraphCubit`-owned state, independent of node identity.

- `GraphState` gains `Map<String, int> hiddenNeighborCounts` (or separate `totalNeighborCounts`/derive hidden on read — either works).
- `GraphCubit._updateGraph` (`graph_cubit.dart:536-600`) recomputes counts after every merge:
  - **Relationships**: `hidden = total - edgesTouching(nodeId)`, where `edgesTouching` counts `graphController.edges` with `source.id == nodeId || destination.id == nodeId`.
  - **Genealogy**: `hidden = total - childEdgesFrom(nodeId)`, counting edges where `source.id == nodeId` (tree edges are ancestor→descendant). **Do not** use `_genealogyChildrenCursors` for this — it only stores `(DateTime, String)` pagination cursors (`graph_cubit.dart:123, 291`), not counts.
- No new fetch-triggering logic is needed — existing tap-driven `_fetch()` calls already merge more edges; the count recompute just needs to run alongside that merge.

## UI wiring

- Reuse `TenturaCountBadge` (`packages/client/lib/design_system/components/tentura_count_badge.dart:6-37`) — same component already used in `tentura_underline_tabs.dart` and `item_card.dart`.
- **Rebuild path is the crux of the UI work.** `GraphBody`'s `BlocBuilder<GraphCubit, GraphState>` only rebuilds `buildWhen: previous.isLoading != current.isLoading` (`graph_body.dart:106`), and `nodeBuilder`/`GraphNodeWidget` instances are created and kept alive by the external `graphController` (`AnimatedBuilder`-driven inside the vendored package), not by `GraphState` changes. A `hiddenNeighborCounts` map sitting on `GraphState` will not, by itself, cause anything to redraw. Fix: wrap just the badge in its own `BlocSelector<GraphCubit, GraphState, int?>` **inside** `GraphNodeWidget`, selecting `state.hiddenNeighborCounts[nodeDetails.id]`. Since `GraphNodeWidget` instances persist across outer rebuilds, this selector is what actually drives the badge to update/disappear independent of the node-content rebuild cycle.
- In `GraphNodeWidget.build` (`graph_node_widget.dart:24-77`), follow the existing `_HelpOffererRing` overlay pattern (lines 82-130): wrap the avatar/content in a `Stack`, add a `Positioned` badge fed by that `BlocSelector`. Render nothing when the count is null or ≤ 0.
- **Zoom legibility**: confirmed there is no existing screen-space/overlay mechanism to reuse. `GraphLayoutView` (in the vendored `force_directed_graphview` package at `/home/vader/MY_SRC/force_directed_graphview`) stacks `EdgesView`, `LabelsView`, `NodesView` all as siblings *inside* the same `InteractiveViewer`-transformed subtree — text labels already shrink at the graph's min scale (`scaleRange.dx = 0.1`, `graph_body.dart:22,157`) with no existing fix, and `GraphController` exposes no public current-scale listenable to build one cheaply. Rather than build new scale-aware infrastructure for v1, accept the same shrink-at-min-zoom behavior badges will inherit as an existing, already-accepted tradeoff for labels. Revisit only if real usage shows the badge specifically (vs. labels) causes confusion — a fix would require extending the vendored package to expose scale, which is a larger, separate task.

## Rollout order

1. Genealogy: aggregate-count queries (focused node + batched child/bootstrap counts) → schema → `GraphState`/`BlocSelector` plumbing → badge UI. Fully scoped, ship first.
2. Relationships graph: `user_trust_edge` degree query (sign-based `positive_only` filtering via stored `prev_sent_weight`) → `mutual_score`-shape change (Postgres type + Hasura metadata) → same client plumbing built in step 1, extended to this graph. Both graphs are now similarly well-scoped; order is a matter of sequencing, not de-risking one before the other.

## Verification

- Server: aggregate-count query tests — page 1 vs. page 2+ (count must stay constant across pages), a zero-children node, and the batched bootstrap/child-node-count query returning correct values for a mixed set of node keys (some with children, some without).
- Client: `GraphCubit` test asserting `hiddenNeighborCounts` is correct after the first page merge and decreases to 0 across subsequent merges, for both genealogy (child-edge-count based) and relationships (touching-edge-count based) modes.
- Widget test: `GraphNodeWidget` badge renders with correct count, disappears at 0/null, and — specifically — that updating only `hiddenNeighborCounts` in `GraphState` (without touching node identity) rebuilds just the badge via `BlocSelector`, not the whole node.
- Server: `user_trust_edge` degree query test covering `positive_only` true/false against a mix of positive- and negative-`prev_sent_weight` edges.
- Manual: run the app (`/run` skill), open both graphs, tap a node with many hidden connections, confirm the badge count drops as more neighbors load and disappears once exhausted.

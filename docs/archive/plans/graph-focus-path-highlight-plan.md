# Focus-path highlighting for the relationships graph

## Context

Tapping a node in the relationships graph calls `GraphCubit.setFocus` (`packages/client/lib/features/graph/ui/bloc/graph_cubit.dart:157-169`), which pins the node, recenters the camera, and fetches its neighbors. But nothing already loaded is ever removed: `_nodes` and `graphController` only grow (`_updateGraph`, `graph_cubit.dart:652-718`, is purely additive — `mutator.addNode`/`addEdge`, no `removeNode`/`removeEdge` calls anywhere in the file today). As a session goes on and the user's attention drifts across the graph, edge count balloons and the view stops being readable.

This plan makes focus a *spotlight*: after a tap, only the chain connecting the ego ("Me") node to the newly focused node stays visible, plus whatever fresh neighbors that tap just revealed. Everything else fades from view until it becomes relevant again (either because focus moves back onto it, or a new path passes through it).

### Example walkthrough

Start: only ego (A) expanded, first-degree neighbors B, C, D visible.

```
        B
       /
  [A]=Me — C
       \
        D
```

Tap **B** → focus = B, fetch returns B's neighbors E, F.

```
  [A]=Me — B — E
             \
              F
```

C, D and edges A–C, A–D disappear (not on the ego→B path, not new neighbors of B). A–B survives (on the path). B–E, B–F appear (fresh neighbors of the new focus).

Tap **E** → focus = E, path is now A→B→E, fetch returns E's neighbors G, H.

```
  [A]=Me — B — E — G
                 \
                  H
```

F disappears too (sibling of E, no longer on the ego→E path), along with B–F. Tapping back on B re-reveals E and F instantly (no refetch — see "Visibility is a pure filter" below) and hides G, H again.

## Design decisions

1. **Path = union of all currently-loaded ego→focus chains**, not a single shortest path. If the graph has a diamond (ego→B→E and ego→C→E both loaded), both branches stay visible when focus = E — hiding one arbitrarily would erase a path the user was just looking at.
2. **Direction: outgoing-only** (`src → dst`, following trust direction out from ego), consistent with how `EdgeDirected` already models trust edges. When ego has no outgoing path to focus (e.g. someone trusts ego but ego never trusted them back), reuse the existing swapped-endpoints fallback described below rather than leaving the node looking disconnected.
3. **Visibility is a pure client-side filter, recomputed on every focus change** — no data is discarded and no refetch happens when backtracking. This requires decoupling "fetched" from "currently rendered," which today are the same thing (see Implementation, step 1).

## Existing precedent to reuse

`packages/client/lib/features/graph/domain/prune_directed_paths.dart` already implements exactly this kind of pruning — `edgesOnSomeDirectedPath({edges, root, focus})` keeps only edges lying on some directed root→focus chain, via forward-reachability-from-root ∩ can-reach-focus, and **already has the swap fallback for decision 2**: if there's no `root → focus` path, it retries `pruneFor(focus, root)` (used today for the forwards/help-offerer graph, where the viewer can be either the author or the help offerer depending on direction — `graph_cubit.dart:266-271`). It is not currently wired into the general MeritRank connections graph.

Two gaps before it's reusable here:

- It operates on `Set<EdgeDirected>` (the raw per-fetch server rows: `src`, `dst`, `weight`, ...). The connections graph never retains a full-history `Set<EdgeDirected>` — each `_fetch()` call only has the latest batch in a local variable. Path pruning needs to see everything fetched so far, not just the last page.
- It's a one-shot function; here it needs to run every time `focus` or the accumulated edge set changes, and its output needs to be reconciled against the live `graphController` (add what's newly visible, remove what's no longer visible) rather than just filtering a list once.

## Implementation

### 1. Persistent full-history edge cache

Add `_allEdges = <(String src, String dst), EdgeDirected>{}` (or similar) to `GraphCubit`, appended to inside `_updateGraph` for every edge processed, regardless of whether it ends up visible. This becomes the new source of truth for path computation ("what have we fetched, so what can `edgesOnSomeDirectedPath` route through") — replacing the current implicit assumption that `graphController.edges` == "everything fetched," an assumption this feature breaks once hiding is introduced.

`_deriveHiddenNeighborCounts` (`graph_cubit.dart:600-635`) needs **no change** and must keep reading `graphController.edges`, not `_allEdges`. Its badge is meant to show precisely what the user currently sees, regardless of *why* something is off-screen — never fetched, or fetched-but-path-hidden makes no difference. Since path-hidden nodes are genuinely removed from `graphController` (step 3 below), the existing `hidden = total - visibleCount` computation already does the right thing for free: tapping a node to reveal its neighbors drops its badge, and later hiding those same neighbors again (by exploring elsewhere) raises the badge back up — no separate signal needed.

### 2. Generalize the path-pruning helper

Extract the BFS core of `edgesOnSomeDirectedPath` to operate on `(String src, String dst)` pairs rather than being hard-coded to `EdgeDirected`, so both the forwards-graph call site and the new connections-graph call site can share it. Add a thin wrapper for each edge type.

Visible-edge computation per focus change:

```
pathEdges = edgesOnSomeDirectedPath(edges: _allEdges.values, root: egoId, focus: focusId)
focusIncidentEdges = { e in _allEdges.values | e.src == focusId || e.dst == focusId }
visibleEdges = pathEdges ∪ focusIncidentEdges
visibleNodeIds = { ego.id, focusId } ∪ endpoints(visibleEdges)
```

`focusIncidentEdges` is the "except the newly shown of course" clause — it's what makes tapping a node reveal its fresh neighbors even though they aren't yet on any ego-rooted path.

### 3. Reconciliation against `graphController`

New `_recomputeVisibility()`, called at the end of `_updateGraph` and after `setFocus`'s pin change:

```dart
graphController.mutate((mutator) {
  for (final node in mutator.controller.nodes) {
    if (node.id != _egoNode.id && !visibleNodeIds.contains(node.id)) {
      mutator.removeNode(node); // cascades to remove touching edges
    }
  }
  for (final id in visibleNodeIds) {
    final node = _nodes[id];
    if (node != null && !mutator.controller.nodes.contains(node)) {
      mutator.addNode(node);
    }
  }
  for (final edge in visibleEdgeDetails) {
    if (!mutator.controller.edges.contains(edge)) {
      mutator.addEdge(edge);
    }
  }
});
```

`GraphController._removeNode` (vendored package, `force_directed_graphview-0.6.2/lib/src/controller.dart:225-232`) already cascades edge removal, so node-level removal is sufficient for the common case; the explicit edge pass covers the rare case of two still-visible nodes whose connecting edge isn't itself on-path or focus-incident (e.g. two of ego's siblings that happen to be linked to each other).

**Known tradeoff**: `_replaceNode`/`_removeNode` drop the node's layout position (`GraphLayoutBuilder...removeNode`). Re-adding a previously-hidden node re-seeds it from its cached `positionHint` rather than the coordinate it was at before it was hidden, so backtracking will show a re-layout "snap" rather than the exact previous arrangement. Acceptable for v1; revisit only if it reads as jarring in practice.

### 4. Pin/unpin fix (independent, but ships alongside this)

`setFocus` currently only ever pins the newly tapped node and never unpins the previous one, so every node ever tapped stays frozen in the force layout forever. Fix in `setFocus`:

```dart
void setFocus(NodeDetails node) {
  if (state.focus != node.id) {
    final previousFocusId = state.focus;
    emit(state.copyWith(focus: node.id));
    graphController.setPinned(node, true);
    if (previousFocusId.isNotEmpty && previousFocusId != _egoNode.id) {
      for (final n in graphController.nodes) {
        if (n.id == previousFocusId && n.pinned) {
          graphController.setPinned(n, false);
          break;
        }
      }
    }
    ...
  }
  ...
}
```

Look up the *live* controller instance by id (not `_nodes[previousFocusId]`, which can be a stale copy — see the existing defensive lookup at `graph_cubit.dart:432-438` for the same reason) before calling `setPinned`, since `NodeBase` equality doesn't include `pinned` but does include `positionHint`/other fields, and `_replaceNode` throws if the passed instance isn't `==` to something currently in the controller's `Set`.

Because each call only ever pins the new focus and unpins the one before it, this converges to "ego + current focus pinned, everything else free" without needing to track a history list — skip the ego id explicitly since it must stay pinned permanently as the layout anchor.

## Scope for v1

Applies only to the default MeritRank connections graph (`forwardsGraphBeaconId == null && !genealogyMode`). The forwards/help-offerer graph already has its own bounded, curated pinning scheme and doesn't suffer the same clutter problem (static, not incrementally explored the same way); genealogy mode has a different browsing pattern (invite tree) and its own ego concept (`state.egoNodeId`). Extending focus-path highlighting to either is a follow-up, not blocked by this plan.

`setContext`/`togglePositiveOnly` already reset `focus` to `''` and call `graphController.clear()` (`graph_cubit.dart:173-209`) — fully compatible as-is; visibility just recomputes from an empty state on the next fetch.

## Badge semantics (resolved)

The `hiddenNeighborCounts` badge is unified, not split by cause: it reports how many of a node's total neighbors aren't currently rendered, whether that's because they were never fetched or because they were fetched and then path-hidden. No new field, no separate indicator. Concretely, across a tap sequence: tapping a node to reveal its neighbors drops that node's badge (they're now visible); continuing to explore elsewhere and having those neighbors path-hidden again raises the badge back up (they're off-screen again, for whatever reason). This falls out of `_deriveHiddenNeighborCounts` unchanged, per the previous section.

## Verification

- `GraphCubit` unit tests: tap sequence A→B→E→back-to-B reproduces the walkthrough above — asserts exact visible node/edge id sets at each step, and that no refetch occurs on the backtrack step (mock repository call count unchanged).
- Diamond case: two loaded paths ego→B→E and ego→C→E, focus = E — both branches stay visible.
- No-outgoing-path case: focus reachable only via an incoming edge — swapped-endpoints fallback produces a connected spine instead of an orphaned node.
- Pin/unpin: after a multi-hop tap sequence, assert only ego and the current focus report `pinned == true` in `graphController.nodes`.
- Badge: tap B (revealing E, F) — B's `hiddenNeighborCounts` entry drops by 2 (or to absent). Tap E next (E's neighbors pull focus onward) — F becomes path-hidden again and B's badge count rises back by 1, with no server call (count comes from `_totalNeighborCounts`, already cached).
- Manual: run the app (`/run` skill), open the relationships graph, drill several levels deep, confirm the view stays uncluttered and backtracking is instant with no loading spinner, and watch badge counts rise/fall as neighbors are revealed and re-hidden.

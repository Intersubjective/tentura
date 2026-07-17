---
status: done
kind: plan
---
# Invite genealogy: bound descendant growth + reuse the trust-graph widget

**Revision 4** — incorporates three rounds of code review. Rev 2 fixed
several implementation-blocking issues from rev 1 (pagination design
contradicted its own clamp, ancestor-chain root nodes would silently drop,
missing DB index, missing V2 routing entry, a method-signature collision, and
a doc-deletion mistake). Rev 3 fixed issues found in rev 2 (offset pagination
still not truly bounded → keyset/cursor pagination; bootstrap/child-fetch
edge duplication with mismatched colors → dedup by endpoint pair; the
defensive `GraphSourceRepository.fetch()` adapter silently producing a broken
graph → fails loudly instead; `_egoNode` handling made concrete;
`EdgeDirected` call sites enumerated). This revision fixes issues found in
rev 3: the keyset query's runtime `$2::boolean IS FALSE OR …` guard isn't
guaranteed to plan as an index range scan (split into two plannable SQL
strings), a cursor with only one of its two fields present silently
restarted pagination instead of erroring (now a resolver-level validation
error), the new universal edge-dedup set (rev 3, §3.2) would go stale across
`graphController.clear()` calls and silently starve the graph of edges after
a context/filter change (now cleared alongside it), the resolver uses raw
`GraphQLFieldInput` instead of this codebase's existing `InputField*` helpers
(which also fixes an unrelated crash-on-malformed-date risk), and a
timing-based "does not measurably regress" test assertion was flagged as
CI-flaky. Rev 1/2/3's architecture stands throughout.

## Problem

`InviteGenealogyRepository.fetchLineage()` (server, own-profile screen) walks
the `invite_genealogy` table with a recursive CTE in **both** directions:
ancestors (bounded — a node has exactly one parent, so it's O(depth)) and
descendants (unbounded — a node can have arbitrarily many children, which can
themselves have arbitrarily many children; fully materializing the subtree of
a prolific inviter is a real DoS-shaped footgun on a query that runs on every
profile view). `fetchLineageBetween()` (other-user's-profile screen) never
had this problem — it only ever walks upward for both endpoints.

Separately, the client currently renders genealogy with a hand-rolled parallel
widget/cubit (`InviteGenealogyGraphBody` / `InviteGenealogyGraphCubit`) instead
of the trust/friendship graph's `GraphBody` / `GraphCubit`, even though the
node-rendering layer (`NodeDetails` sealed type, `GraphNodeWidget`) already has
first-class `GenealogyUserNode` / `GenealogyDeletedNode` variants wired in —
this looks like an earlier, unfinished step toward exactly this reuse.

## Decisions locked in

- **Own-profile initial load is ancestors only.** No descendants (not even a
  first page) are returned until the viewer taps a node. This applies
  **uniformly to every node, not just the viewer's own** — tapping any loaded
  ancestor reveals *that ancestor's* direct children (which may include
  siblings unrelated to the viewer). There is no special-cased "self first"
  ordering; every node behaves identically the first time it's tapped.
- **Descendant exploration is unrestricted but bounded per tap**, same trust
  model as today's trust graph. Precisely: the server enforces no ownership
  or reachability check on `node_key` at all — any authenticated caller can
  request children of *any* valid node key, not only ones the client
  happened to reach by tapping through the UI (the UI's tap-driven flow is
  what bounds *discovery*, not what the server enforces; the server-side
  boundary is "authenticated + well-formed key", full stop). This is
  acceptable because node keys are opaque HMAC-derived values (§ below) —
  not enumerable or guessable — so in practice reaching an arbitrary node
  still requires having legitimately observed its key first, same as the
  trust graph's existing exposure model today. Each tap/call only pulls a
  small bounded window, so no single request can be expensive regardless of
  which node it targets.
- **No upward pagination anywhere.** Ancestor chains are cheap (O(depth)) and
  are always returned in full, immediately, in both modes.
  `fetchLineageBetween` already walks both endpoints to the *root*, not just
  to the common ancestor — that's more than "path to LCA" but it's free, so
  keep it. There is nothing further "up" to reveal past what's already
  returned; only downward (children) exploration is new.

## Why "reuse `GraphBody`/`GraphCubit` with zero changes" isn't quite right

The widget shell (`GraphBody`, `GraphNodeWidget`, `NodeDetails`) is genuinely
data-agnostic already and needs no changes. `GraphCubit` needs a **new,
narrow, additive mode**, for five concrete reasons:

1. **Synthetic ego node.** `GraphCubit` always fabricates a fake
   `UserNode(user: me, id: me.id)` and unconditionally adds it to the graph.
   Genealogy has no such thing — the viewer is a real node keyed by an opaque
   `nodeKey`, not their account id.
2. **Node identity is deliberately not the account id.**
   `InviteGenealogyNodeKey.derive()` (server) HMACs the user id specifically
   so a deleted account's tree position can't be correlated to a live id from
   the client. `GraphCubit._resolveNodeById`'s lazy fallback
   (`id.startsWith('U') → fetch profile by id`) must never fire for a
   genealogy edge.
3. **`EdgeDirected.node` only ever describes the destination endpoint.**
   `GraphCubit._fetch()` attaches `e.node` to `_nodes[e.dst]`; `e.src` is
   *always* lazy-resolved by id prefix (`U…`/`B…`), with no payload path at
   all (`graph_cubit.dart:239-267`). An ancestor **chain** modeled as
   `src = ancestor, dst = descendant` has exactly one endpoint (the topmost
   root) that never appears as anyone's `dst` — it would silently be dropped,
   since genealogy ids start with `G`, not `U`/`B`, so the prefix-based
   fallback returns `null` for it. This isn't a hypothetical edge case, it's
   guaranteed to hit the root of every chain on every bootstrap fetch. Fixed
   in Part 3 below by having the cubit preload *all* nodes for a payload
   directly, independent of edge direction — not by widening `EdgeDirected`.
4. **Pairwise branch coloring has no equivalent today.** The standalone
   cubit's `_branchBelowLca` (ego-branch / target-branch / neutral-trunk
   3-way coloring for the "between" view) is graph-topology logic that
   `GraphCubit._updateGraph`'s simple "touches the one ego node" rule can't
   express.
5. **The "hide negative edges" side control is meaningless** for a DAG with
   no negative weights and must be suppressed, not left as a dead button.

Follows the **existing precedent** for this exact situation:
`ForwardsGraphRepository` already coexists with the MeritRank
`GraphSourceRepository.fetch()` contract by implementing the marker interface
for DI/typing purposes only, while `GraphCubit._fetch()` type-checks
`source is ForwardsGraphRepository` and calls dedicated, differently-shaped
methods directly. Genealogy does the same.

**Layering rule for the whole plan:** the genealogy *repository* returns
plain domain data (`InviteGenealogyGraph`, `InviteGenealogyNode`,
`InviteGenealogyEdge` — types that already exist and already carry no UI
concerns) plus a bare topology classification where needed. It never
constructs `NodeDetails`, `Color`, or reads L10n strings — that translation
happens in `GraphCubit`, which already owns exactly this kind of decision for
the other two modes (e.g. its existing ego-touch → color rule) and already
receives `GraphEdgeColors` in its constructor.

## Part 1 — Server

### 1.1 Fix the unbounded query (`packages/server/lib/data/repository/invite_genealogy_repository.dart`)

- Rewrite `fetchLineage()` to reuse the existing `_fetchAncestorEdgeRows()`
  helper (already used by `fetchLineageBetween`) instead of `_fetchEdgeRows()`
  — i.e. drop the `descendants` CTE and its `UNION` entirely. `fetchLineage`
  becomes "ancestor chain of one user," structurally identical to one side of
  `fetchLineageBetween`.
- Delete `_fetchEdgeRows()` (the bidirectional recursive CTE) — dead code
  once `fetchLineage` no longer needs it.
- Add a new method using **keyset (cursor) pagination**, not `OFFSET`. An
  `OFFSET`-based page still forces Postgres to walk and discard every skipped
  row even with the composite index in §1.2 — a client-supplied `offset`
  (these are ordinary GraphQL variables, not something only reachable by
  tapping N times in the real app) is effectively an uncapped "do O(offset)
  work" knob, which undermines the whole point of bounding this query. A
  cursor built from the last-seen row's sort key has no such knob — each call
  does a bounded index range scan regardless of how deep into a node's
  children the caller has already paged:

  **Two separate SQL strings, not one query with a runtime branch.** A
  single query with a `$2::boolean IS FALSE OR (row) > (…)` guard makes the
  planner choose one plan shape that has to stay correct for both boolean
  values of `$2` — with `customSelect`'s parameterized/potentially-cached
  plan, that's not guaranteed to come out as the clean index range scan the
  row-comparison form gives you on its own. Splitting into "first page" (no
  cursor predicate at all) and "next page" (a bare, unconditional row
  comparison) queries means each one is trivially plannable as an index
  range scan with nothing to second-guess:

  ```dart
  Future<InviteGenealogyChildrenPageEntity> fetchChildren({
    required String nodeKey,
    required int limit,
    DateTime? afterCreatedAt,
    String? afterNodeKey,
  }) async {
    // Caller (resolver, §1.8) already rejects a mismatched pair -- both
    // present or both null by the time this is reached.
    final clampedLimit = limit.clamp(1, _maxChildrenPageSize); // e.g. 50
    final rows = afterCreatedAt != null && afterNodeKey != null
        ? await _database.customSelect(
            r'''
  SELECT ancestor_node_key, descendant_node_key, ancestor_user_id, descendant_user_id,
         ancestor_user_created_at, descendant_user_created_at,
         ancestor_deleted_at, descendant_deleted_at, created_at
  FROM invite_genealogy
  WHERE ancestor_node_key = $1
    AND (descendant_user_created_at, descendant_node_key) > ($2, $3)
  ORDER BY descendant_user_created_at ASC, descendant_node_key ASC
  LIMIT $4
  ''',
            variables: [
              Variable<String>(nodeKey),
              Variable<PgDateTime>(PgDateTime(afterCreatedAt)),
              Variable<String>(afterNodeKey),
              Variable<int>(clampedLimit),
            ],
            readsFrom: {_database.inviteGenealogy},
          ).get()
        : await _database.customSelect(
            r'''
  SELECT ancestor_node_key, descendant_node_key, ancestor_user_id, descendant_user_id,
         ancestor_user_created_at, descendant_user_created_at,
         ancestor_deleted_at, descendant_deleted_at, created_at
  FROM invite_genealogy
  WHERE ancestor_node_key = $1
  ORDER BY descendant_user_created_at ASC, descendant_node_key ASC
  LIMIT $2
  ''',
            variables: [
              Variable<String>(nodeKey),
              Variable<int>(clampedLimit),
            ],
            readsFrom: {_database.inviteGenealogy},
          ).get();
    final edgeRows = rows.map(_EdgeRow.fromQueryRow).toList();
    final edges = [
      for (final row in edgeRows)
        InviteGenealogyEdgeEntity(
          ancestorNodeKey: row.ancestorNodeKey,
          descendantNodeKey: row.descendantNodeKey,
          ancestorUserCreatedAt: row.ancestorUserCreatedAt,
          descendantUserCreatedAt: row.descendantUserCreatedAt,
          createdAt: row.createdAt,
        ),
    ];
    final nodes = await _buildNodes(edgeRows: edgeRows, seedNodeKeys: const {});
    return InviteGenealogyChildrenPageEntity(nodes: nodes, edges: edges);
  }
  ```

  The `(descendant_user_created_at, descendant_node_key) > (…, …)` row
  comparison is standard Postgres keyset syntax and matches the composite
  index's column order from §1.2 exactly. `descendant_node_key` as the
  tiebreaker is still required for determinism when two children share a
  `created_at`.

  **This method trusts its caller on the cursor pair being both-or-neither**
  — see §1.8, which validates that at the resolver (GraphQL/API boundary)
  before this method is ever reached, so it doesn't need to re-check here.

  The client calls this with a **fixed page size and the cursor from the
  previous page's last row** (§3.2), never an offset/count. This also means
  there's nothing for the client to get "wrong" by miscounting — it doesn't
  track how many children it has seen, only the identity of the last one.

### 1.2 Add a composite index (new migration)

The only existing index is single-column
(`invite_genealogy_ancestor_node_key`, `m0106.dart:29`). `WHERE
ancestor_node_key = $1 ORDER BY descendant_user_created_at, descendant_node_key`
can use that index to filter but still has to sort every matching row before
`LIMIT`/`OFFSET` can apply — for a node with a large fan-out (exactly the case
this whole feature exists to bound), that means reading and sorting the full
child set on every single page request, defeating the point. Add
`packages/server/lib/data/database/migration/m0107.dart`:

```dart
part of '_migrations.dart';

final m0107 = Migration('0107', [
  '''
DROP INDEX IF EXISTS public.invite_genealogy_ancestor_node_key;
''',
  '''
CREATE INDEX invite_genealogy_ancestor_node_key_children_page
  ON public.invite_genealogy (ancestor_node_key, descendant_user_created_at, descendant_node_key);
''',
]);
```

Register it in `_migrations.dart` (`part 'm0107.dart';` and append `m0107` to
the migrations list), matching the existing pattern for `m0106`. Dropping the
old single-column index is safe — the new composite index's leading column is
still `ancestor_node_key`, so it serves every existing query that used the old
index (e.g. any lookup by ancestor alone) at no cost.

### 1.3 Entity (`packages/server/lib/domain/entity/invite_genealogy_graph_entity.dart`)

Add:

```dart
@freezed
abstract class InviteGenealogyChildrenPageEntity
    with _$InviteGenealogyChildrenPageEntity {
  const factory InviteGenealogyChildrenPageEntity({
    required List<InviteGenealogyNodeEntity> nodes,
    required List<InviteGenealogyEdgeEntity> edges,
  }) = _InviteGenealogyChildrenPageEntity;
}
```

Run `build_runner` for this file (new `.freezed.dart` part) same as any other
freezed entity change in this package.

### 1.4 Port (`packages/server/lib/domain/port/invite_genealogy_repository_port.dart`)

Add `fetchChildren` to the abstract port (and to
`packages/server/lib/data/repository/mock/invite_genealogy_repository_mock.dart`
— return a small canned page).

### 1.5 Use case (`packages/server/lib/domain/use_case/invite_genealogy_case.dart`)

Add a pass-through:

```dart
Future<InviteGenealogyChildrenPageEntity> fetchChildren({
  required String nodeKey,
  DateTime? afterCreatedAt,
  String? afterNodeKey,
  required int limit,
}) => _repository.fetchChildren(
  nodeKey: nodeKey,
  afterCreatedAt: afterCreatedAt,
  afterNodeKey: afterNodeKey,
  limit: limit,
);
```

No authorization narrowing beyond "must be authenticated" — matches the
"unrestricted, bounded per tap" decision above. Don't add a subtree-ownership
check; it wasn't asked for and would need its own design (walking the caller's
own ancestor/descendant closure on every expand call, which reintroduces an
unbounded query).

### 1.6 GraphQL type (`packages/server/lib/api/controllers/graphql/custom_types.dart`)

Add, right after `gqlTypeInviteGenealogy` (reusing the existing
`gqlTypeInviteGenealogyNode` / `gqlTypeInviteGenealogyEdge` types as-is):

```dart
final gqlTypeInviteGenealogyChildrenPage =
    GraphQLObjectType('InviteGenealogyChildrenPage', null)
      ..fields.addAll([
        field('nodes', GraphQLListType(gqlTypeInviteGenealogyNode.nonNullable())),
        field('edges', GraphQLListType(gqlTypeInviteGenealogyEdge.nonNullable())),
      ]);
```

Register it in the `customTypes` list in the same file (next to
`gqlTypeInviteGenealogy`).

### 1.7 Mapper (`packages/server/lib/api/controllers/graphql/mappers/invite_genealogy_gql_maps.dart`)

Add, composing the existing `inviteGenealogyNodeToGqlMap` /
`inviteGenealogyEdgeToGqlMap`:

```dart
Map<String, dynamic> inviteGenealogyChildrenPageToGqlMap(
  InviteGenealogyChildrenPageEntity page, {
  required Map<String, dynamic> Function(UserPublicRecord) userPublicToGqlMap,
}) => {
  'nodes': [
    for (final node in page.nodes)
      inviteGenealogyNodeToGqlMap(node, userPublicToGqlMap: userPublicToGqlMap),
  ],
  'edges': [
    for (final edge in page.edges) inviteGenealogyEdgeToGqlMap(edge),
  ],
};
```

### 1.8 Resolver (`packages/server/lib/api/controllers/graphql/query/query_invite_genealogy.dart`)

Add a `node_key` / `after_created_at` / `after_node_key` / `limit` field,
mirroring `_targetId`'s pattern — but built from this codebase's existing
`InputField*` helpers (`packages/server/lib/api/controllers/graphql/input/
_input_types.dart`), the same way `QueryNotificationCenter` does for its own
cursor-shaped `before`/`limit` args
(`query_notification_center.dart:36-38,63-64`), rather than raw
`GraphQLFieldInput`. This isn't just style consistency —
`InputFieldDatetime.fromArgs` uses `DateTime.tryParse` internally (returns
`null` on a malformed value instead of throwing), where a raw
`DateTime.parse` would let a malformed `after_created_at` crash the resolver
with an uncaught `FormatException` instead of a clean GraphQL error.

Still requires authentication (call `getCredentials(args)` for its
side-effect of throwing when unauthenticated — don't bind it to an unused
`jwt` variable, unlike `inviteGenealogy`'s existing style, since nothing here
reads claims off it). And validate the cursor pair explicitly: if exactly one
of `after_created_at` / `after_node_key` is present, that's a malformed
request, not "start from page 1" — silently restarting pagination would mask
a client bug (or let a crafted request always land on page 1 regardless of
what it claims to be resuming from). Reject it the same way
`mutation_user_vote.dart:62` rejects an invalid vote value — `ArgumentError`
from the resolver, not a silent fallback:

```dart
static final _nodeKey = InputFieldString(fieldName: 'node_key');
static final _afterCreatedAt = InputFieldDatetime(fieldName: 'after_created_at');
static final _afterNodeKey = InputFieldString(fieldName: 'after_node_key');
static final _limit = InputFieldInt(fieldName: 'limit');

List<GraphQLObjectField<dynamic, dynamic>> get all => [
  inviteGenealogy,
  inviteGenealogyBetween,
  inviteGenealogyChildren,
];

GraphQLObjectField<dynamic, dynamic> get inviteGenealogyChildren =>
    GraphQLObjectField(
      'inviteGenealogyChildren',
      gqlTypeInviteGenealogyChildrenPage,
      arguments: [
        _nodeKey.field,
        _afterCreatedAt.fieldNullable,
        _afterNodeKey.fieldNullable,
        _limit.fieldNullable,
      ],
      resolve: (_, args) async {
        getCredentials(args); // authenticated callers only; claims unused here
        final afterCreatedAt = _afterCreatedAt.fromArgs(args);
        final afterNodeKey = _afterNodeKey.fromArgs(args);
        if ((afterCreatedAt == null) != (afterNodeKey == null)) {
          throw ArgumentError(
            'after_created_at and after_node_key must both be provided or both omitted',
          );
        }
        final page = await _inviteGenealogyCase.fetchChildren(
          nodeKey: _nodeKey.fromArgsNonNullable(args),
          afterCreatedAt: afterCreatedAt,
          afterNodeKey: afterNodeKey,
          limit: _limit.fromArgs(args) ?? 10,
        );
        return inviteGenealogyChildrenPageToGqlMap(
          page,
          userPublicToGqlMap: userPublicToGqlMap,
        );
      },
    );
```

(Add the matching `fetchChildren({required String nodeKey, DateTime?
afterCreatedAt, String? afterNodeKey, required int limit})` signature change
through the port and use-case pass-through in §1.4/§1.5 too — both are
one-line signature updates. The port/use-case/repository layers don't need
their own XOR check — they trust the resolver, which is the actual input
boundary; see the note at the end of §1.1.)

### 1.9 Server tests

- Update `test/data/repository/invite_genealogy_repository_test.dart`:
  `fetchLineage` assertions must change to reflect ancestors-only (add a
  fixture with descendants and assert they're **absent** from the result —
  this is the regression test for the actual bug).
- Add `test/data/repository/invite_genealogy_repository_children_test.dart`:
  cover cursor pagination (feeding page N's last row's cursor into page N+1
  across repeated calls with a fixed limit yields the next slice with no
  overlap/gap, not just a single call), the server-side clamp on `limit`,
  ordering stability (tie-break on `descendant_node_key` when timestamps
  collide), a node with zero children returning an empty page (not an
  error), and a malformed cursor pair (one of `afterCreatedAt`/`afterNodeKey`
  set, the other `null`) being rejected — as an `ArgumentError` at the
  resolver level (§1.8), not something this repository test needs to
  duplicate. **Do not** assert on query timing/latency here (e.g. "a deep
  cursor isn't measurably slower than a shallow one") — that's a correctness
  property this suite can't reliably observe without becoming flaky under
  CI's variable load. If the composite index's effectiveness needs
  verification, do it once as a manual `EXPLAIN (ANALYZE, BUFFERS)` check
  against a seeded large-fanout fixture during implementation/review (confirm
  it shows an index range scan, not a sort or seq scan), not as a repeatable
  automated assertion.
- Update `test/domain/use_case/invite_genealogy_case_test.dart` for the new
  pass-through method.

## Part 2 — Client data layer

### 2.1 GraphQL document

New file `packages/client/lib/features/invite_genealogy/data/gql/invite_genealogy_children_fetch.graphql`:

```graphql
# import '/data/gql/user_public_model.graphql'

query InviteGenealogyChildren(
  $nodeKey: String!,
  $afterCreatedAt: String,
  $afterNodeKey: String,
  $limit: Int = 10
) {
  inviteGenealogyChildren(
    node_key: $nodeKey,
    after_created_at: $afterCreatedAt,
    after_node_key: $afterNodeKey,
    limit: $limit
  ) {
    nodes {
      node_key
      deleted_at
      user_created_at
      user { ...UserPublicModel }
    }
    edges {
      ancestor_node_key
      descendant_node_key
      ancestor_user_created_at
      descendant_user_created_at
      created_at
    }
  }
}
```

Run codegen after adding this. The two *existing* documents
(`invite_genealogy_fetch.graphql`, `invite_genealogy_between_fetch.graphql`)
are **not touched or deleted** — see §2.2, the bootstrap path keeps using
them unchanged.

**Do not forget:** add `'InviteGenealogyChildren'` to
`_tenturaDirectOperationNames` in
`packages/client/lib/data/service/remote_api_client/build_client.dart`
(currently lines ~181-182 already list `'InviteGenealogy'` and
`'InviteGenealogyBetween'`). Skipping this routes the new query through
Hasura instead of the V2 server, which doesn't have this resolver — this is
*exactly* the class of bug that produced the `inviteGenealogyBetween`/
`query_root` incident that motivated verifying the deploy in the first place.

### 2.2 `InviteGenealogyRepository` (`packages/client/lib/features/invite_genealogy/data/repository/invite_genealogy_repository.dart`)

**Rename, don't replace, the existing methods**, and add one new one. This
repository will now `implements GraphSourceRepository` (needed purely so it
can be assigned to `GraphCubit`'s `graphSourceRepository` constructor
parameter, same as `ForwardsGraphRepository`). That interface declares
`Future<Set<EdgeDirected>> fetch({bool positiveOnly = true, ...six named
params...})` — the *existing* zero-argument `fetch()` method cannot stand as
an override of that (Dart requires an overriding method to accept every
named parameter the interface declares; a zero-arg method doesn't). So:

- Rename current `fetch()` body → `fetchGenealogyBootstrap({String?
  targetId})`, folding in what `fetchBetween` used to do:

  ```dart
  Future<InviteGenealogyGraph> fetchGenealogyBootstrap({String? targetId}) =>
      targetId == null ? _fetchOwnAncestors() : _fetchAncestorsBetween(targetId);

  Future<InviteGenealogyGraph> _fetchOwnAncestors() async {
    // exact existing body of today's fetch()
  }

  Future<InviteGenealogyGraph> _fetchAncestorsBetween(String targetId) async {
    // exact existing body of today's fetchBetween()
  }
  ```

  No change to the GraphQL request construction or response mapping in
  either branch — `fetchLineage`'s server-side behavior change (§1.1) is
  transparent to this method; it already only ever consumed `graph.nodes` /
  `graph.edges` generically.

- Add the new paginated method, returning plain domain types (no
  `NodeDetails`, no `Color`, no L10n):

  ```dart
  Future<InviteGenealogyChildrenPage> fetchChildren({
    required String nodeKey,
    DateTime? afterCreatedAt,
    String? afterNodeKey,
    required int limit,
  }) async {
    final data = await requestDataOnlineOrThrow(
      GInviteGenealogyChildrenReq(
        (b) => b
          ..vars.nodeKey = nodeKey
          ..vars.afterCreatedAt = afterCreatedAt?.toUtc().toIso8601String()
          ..vars.afterNodeKey = afterNodeKey
          ..vars.limit = limit,
      ),
      label: _label,
    );
    final page = data.inviteGenealogyChildren;
    if (page == null) {
      return const (nodes: <InviteGenealogyNode>[], edges: <InviteGenealogyEdge>[]);
    }
    return (
      nodes: [
        for (final n in page.nodes)
          InviteGenealogyNode(
            nodeKey: n.node_key,
            profile: n.user == null ? null : (n.user! as UserPublicModel).toEntity(),
            deletedAt: _parseDate(n.deleted_at),
            userCreatedAt: _parseDate(n.user_created_at),
          ),
      ],
      edges: [
        for (final e in page.edges)
          InviteGenealogyEdge(
            ancestorNodeKey: e.ancestor_node_key,
            descendantNodeKey: e.descendant_node_key,
            ancestorUserCreatedAt: _parseDate(e.ancestor_user_created_at)!,
            descendantUserCreatedAt: _parseDate(e.descendant_user_created_at)!,
            createdAt: _parseDate(e.created_at)!,
          ),
      ],
    );
  }
  ```

  Add the typedef next to `InviteGenealogyGraph` in
  `packages/client/lib/features/invite_genealogy/domain/entity/invite_genealogy_graph.dart`:

  ```dart
  typedef InviteGenealogyChildrenPage = ({
    List<InviteGenealogyNode> nodes,
    List<InviteGenealogyEdge> edges,
  });
  ```

- Implement the `GraphSourceRepository` marker method to **fail loudly**, not
  defensively. Rev 2 of this plan had it silently return `G…`-keyed edges
  with `node: null` — but the generic (non-genealogy-mode) `GraphCubit` code
  path that would call this can only lazy-resolve `U…`/`B…`-prefixed ids
  (§"why zero changes isn't realistic", reason 3); handed a `G…` id, it
  silently drops the node and renders an empty or broken-looking graph with
  no error anywhere. That's strictly worse than failing fast, since it's the
  kind of bug that only surfaces as "the graph looks empty" in manual
  testing with no stack trace to follow. This method is never meant to be
  called at all — `GraphCubit`'s genealogy branch always calls
  `fetchGenealogyBootstrap`/`fetchChildren` directly via a type-check, same
  as `ForwardsGraphRepository` — so make that contract explicit:

  ```dart
  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
  }) => throw UnsupportedError(
    'InviteGenealogyRepository only supports fetchGenealogyBootstrap/'
    'fetchChildren via GraphCubit(genealogyMode: true); the generic '
    'GraphSourceRepository.fetch() contract (U…/B… id resolution, signed '
    'weight) does not apply to genealogy node keys.',
  );
  ```

  (This only exists so `InviteGenealogyRepository` type-checks against
  `GraphCubit`'s `graphSourceRepository: GraphSourceRepository?` constructor
  parameter — implementing the interface is required for that assignment to
  compile, but nothing should ever invoke this specific method. If that
  becomes awkward in practice, the alternative is widening `GraphCubit`'s
  constructor parameter type instead of forcing every source through one
  interface — a bigger change, worth reconsidering only if this method's
  `throw` actually gets hit somewhere during implementation.)

- **Hard invariant, unit-test it:** `GraphCubit`'s genealogy branch (Part 3)
  must never rely on `EdgeDirected.node`/lazy prefix resolution for these
  edges — it preloads nodes from `InviteGenealogyGraph.nodes` /
  `InviteGenealogyChildrenPage.nodes` directly. This repository doesn't need
  to change to support that; it already returns full node lists alongside
  edges (`InviteGenealogyGraph.nodes` already includes isolated/rootless
  nodes today — see the existing `edgeRows.isEmpty` branch in
  `fetchLineage`/`fetchLineageBetween` on the server, which already returns a
  single-node graph with no edges for a user with no ancestors).

## Part 3 — `GraphCubit` / `EdgeDirected`: the new genealogy mode

### 3.1 `EdgeDirected` (`packages/client/lib/features/graph/domain/entity/edge_directed.dart`)

Add one nullable **topology tag**, not a baked `Color` (color stays a
`GraphCubit`-owned decision, consistent with the layering rule above):

```dart
enum GenealogyEdgeBranch { ego, target, neutral }

typedef EdgeDirected = ({
  String src,
  String dst,
  double weight,
  NodeDetails? node,
  GenealogyEdgeBranch? branch, // only set by genealogy "between" mode; null everywhere else
});
```

`EdgeDirected` is a record type, so every literal constructing one needs the
new field added explicitly (records have no optional-with-default fields the
way class constructors do — omitting `branch` is a compile error even though
its type is nullable). This is a mechanical but blocking change at every
existing call site that builds an `EdgeDirected` literal directly:

- `packages/client/lib/features/graph/data/repository/graph_repository.dart:52`
  and `:60` (the `UserNode`/`BeaconNode` branches of `GraphRepository.fetch`)
- `packages/client/lib/features/graph/data/repository/forwards_graph_repository.dart:45`
  and `:78`
- `packages/client/test/features/graph/prune_directed_paths_test.dart:8-13`
  — the `_e(String src, String dst)` test helper builds a bare `EdgeDirected`
  record; add `branch: null` there or the whole test file fails to compile,
  not just the genealogy-related tests. Grep for `EdgeDirected` and for
  record literals shaped like `(src: ..., dst: ..., weight: ...` across both
  `lib/` and `test/` before considering this done — the four sites above are
  everything found as of this plan, but re-verify at implementation time in
  case something else was added in the meantime.

Add `branch: null` at all of them (the §2.2 defensive `fetch()` adapter no
longer needs one — it throws instead of constructing edges, per the fix
above).

### 3.2 `GraphCubit` (`packages/client/lib/features/graph/ui/bloc/graph_cubit.dart`)

- New constructor params, parallel to `forwardsGraphBeaconId`:

  ```dart
  /// When true, this cubit runs in invite-genealogy mode: ancestors load in
  /// full immediately, descendants load one bounded page per tap via
  /// InviteGenealogyRepository.fetchChildren. Mutually exclusive with
  /// forwardsGraphBeaconId / helpOffererFocusUserId.
  final bool genealogyMode;

  /// Genealogy "between" mode target user id; null = own-profile ancestors only.
  final String? genealogyTargetId;

  /// Localized label for GenealogyDeletedNode (genealogy mode only).
  final String? genealogyAnonymousNodeLabel;
  ```

- **`_egoNode` stays exactly as it is today — a non-nullable `final` field,
  always constructed in the initializer list.** Making it nullable would
  ripple through every other call site that currently assumes a non-null
  `UserNode` (`jumpToEgo`, the unconditional add in `_updateGraph`,
  `_egoNode.id` comparisons elsewhere), which is a much wider diff than this
  plan needs. Instead, gate the two places `_egoNode` actually *enters the
  graph*:

  1. `_nodes`'s `late final` initializer (currently
     `<String, NodeDetails>{_egoNode.id: _egoNode}` at
     `graph_cubit.dart:102-104`) becomes conditional:

     ```dart
     late final Map<String, NodeDetails> _nodes = genealogyMode
         ? <String, NodeDetails>{}
         : <String, NodeDetails>{_egoNode.id: _egoNode};
     ```

     (Safe ordering-wise: `late final` runs on first access, well after the
     constructor body completes, so `genealogyMode` — itself set in the
     initializer list — is already available.)

  2. `_updateGraph`'s unconditional
     `if (!mutator.controller.nodes.contains(_egoNode)) mutator.addNode(_egoNode);`
     gets an `if (!genealogyMode)` guard around it.

  `_egoNode` itself remains a harmless, never-rendered object in genealogy
  mode — it's just never added to `_nodes` or the controller, so it can
  never appear on screen or be jumped to.

- Add two new `GraphState` fields, both empty until the bootstrap response
  arrives: `egoNodeId` and `genealogyTargetNodeKey` (needed to decide which
  nodes get pinned/enlarged when converting to `NodeDetails`, and to compute
  branch classification).

- `jumpToEgo()`:

  ```dart
  void jumpToEgo() {
    final node = genealogyMode ? _nodes[state.egoNodeId] : _egoNode;
    if (node == null) return;
    graphController.jumpToNode(node);
  }
  ```

- One new private field for pagination bookkeeping — a cursor per expanded
  node, not a count/offset (the server switched to keyset pagination in
  §1.1, so the client tracks the same thing the server needs to resume: the
  last row it actually saw for that node, not how many rows it's seen):

  ```dart
  final _genealogyChildrenCursors = <String, (DateTime, String)?>{};
  ```

  A missing entry means "never fetched"; a `null` value (once added) would
  mean "fetched and exhausted" if the optional exhausted-tracking from the
  note below gets implemented — for the minimal version, a missing entry is
  enough and every tap just calls with `afterCreatedAt: null, afterNodeKey:
  null` the first time.

- New branch in `_fetch()`, parallel to the forwards-graph branch. The
  discriminator is the same one already used for the MeritRank branch —
  `fetchFocus.isEmpty` means "nothing tapped yet" (bootstrap); `state.focus`
  only ever changes via `setFocus`, so this is unambiguous and requires no
  extra state:

  ```dart
  } else if (genealogyMode && source is InviteGenealogyRepository) {
    final InviteGenealogyGraph graph;
    List<EdgeDirected> rawEdges;
    if (fetchFocus.isEmpty) {
      graph = await source.fetchGenealogyBootstrap(targetId: genealogyTargetId);
      if (state.egoNodeId.isEmpty) {
        emit(state.copyWith(
          egoNodeId: graph.viewerNodeKey,
          genealogyTargetNodeKey: graph.targetNodeKey ?? '',
        ));
      }
      rawEdges = _genealogyEdgesFromGraph(graph); // computes branch tags, see below
      _preloadGenealogyNodes(graph.nodes);        // see below -- fixes the root-node-drop issue
    } else {
      final cursor = _genealogyChildrenCursors[fetchFocus];
      final page = await source.fetchChildren(
        nodeKey: fetchFocus,
        afterCreatedAt: cursor?.$1,
        afterNodeKey: cursor?.$2,
        limit: kFetchWindowSize,
      );
      if (page.edges.isNotEmpty) {
        final last = page.edges.last;
        _genealogyChildrenCursors[fetchFocus] =
            (last.descendantUserCreatedAt, last.descendantNodeKey);
      }
      rawEdges = [
        for (final e in page.edges)
          (src: e.ancestorNodeKey, dst: e.descendantNodeKey, weight: 0.0, node: null, branch: null),
      ];
      _preloadGenealogyNodes(page.nodes);
    }
    edges = rawEdges.toSet();
  }
  ```

  Re-tapping an already-expanded node (the trust-graph "second tap on
  focused node" pattern) naturally resumes from that node's stored cursor
  and returns the *next* page, not the same one — no separate
  "already-open" bookkeeping needed.

  `_preloadGenealogyNodes` converts every `InviteGenealogyNode` in the
  payload — **both endpoints of every edge, regardless of direction** — into
  `NodeDetails` and adds it to `_nodes` *before* `edges` is processed by the
  existing generic loops below. This is what fixes reason 3 in the "why zero
  changes isn't realistic" section: because every node a payload could
  possibly reference is preloaded up front, the existing
  `if (_nodes.containsKey(e.src)) continue;` / same-for-`e.dst` loops always
  find their nodes already present and never fall through to the `U`/`B`
  prefix-based lazy resolver, so it's structurally impossible for a
  genealogy edge to hit that path:

  ```dart
  void _preloadGenealogyNodes(List<InviteGenealogyNode> nodes) {
    for (final n in nodes) {
      _nodes.putIfAbsent(n.nodeKey, () {
        final isEndpoint = n.nodeKey == state.egoNodeId ||
            n.nodeKey == state.genealogyTargetNodeKey;
        if (n.profile != null && n.deletedAt == null) {
          return GenealogyUserNode(
            nodeKey: n.nodeKey,
            user: n.profile!,
            pinned: isEndpoint,
            size: isEndpoint ? 72 : 48,
            positionHint: _nodes.length,
          );
        }
        return GenealogyDeletedNode(
          nodeKey: n.nodeKey,
          label: genealogyAnonymousNodeLabel ?? '',
          pinned: isEndpoint,
          size: isEndpoint ? 72 : 48,
          positionHint: _nodes.length,
        );
      });
    }
  }
  ```

  `_genealogyEdgesFromGraph` ports `InviteGenealogyGraphCubit._branchBelowLca`
  verbatim (same algorithm, relocated) to tag each bootstrap edge for the
  "between" case; for the own-profile case (`genealogyTargetId == null`)
  every edge just gets `branch: null` and falls through to the default
  ego-touch coloring in `_updateGraph` (see below), which is correct there
  since there's only one anchor point.

- **Dedup edges by endpoint pair, not by full `EdgeDetails` equality.** This
  is a real, common-path bug, not a hypothetical: bootstrap loads the full
  ancestor chain with branch colors baked in (e.g. `grandparent → parent`
  colored `ego`). The very first natural thing a user does is tap one of
  those ancestor nodes to explore its children — and `fetchChildren
  (grandparent)` returns *all* of grandparent's direct children, which
  includes `parent`, i.e. the exact same edge, now with `branch: null`
  (default/neutral) instead of its bootstrap color. `EdgeDetails.==`
  (`edge_details.dart:24-32`) includes `color` and `strokeWidth`, so
  `_updateGraph`'s existing `!mutator.controller.edges.contains(edge)` check
  does **not** catch this — two `EdgeDetails` with the same endpoints but
  different colors compare unequal, so both get added, producing a visible
  double edge between the same two nodes. Fix: track endpoint pairs
  explicitly and skip re-adding regardless of color, which also happens to
  be the semantically correct behavior — the bootstrap branch color should
  win, and a later duplicate should be silently dropped, not redrawn
  neutral. Apply this universally (not just in genealogy mode) since it's a
  strict improvement and replaces two mechanisms with one:

  ```dart
  final _addedEdgeEndpoints = <(String, String)>{};
  ```

  In `_updateGraph`, replace the existing
  `if (src.id != dst.id && !mutator.controller.edges.contains(edge)) mutator.addEdge(edge);`
  with:

  ```dart
  final endpointKey = (src.id, dst.id);
  if (src.id != dst.id && _addedEdgeEndpoints.add(endpointKey)) {
    mutator.addEdge(edge);
  }
  ```

  (`Set.add` returns `false` if the element was already present, so this is
  a single check-and-insert.)

  **This set must be cleared everywhere `graphController.clear()` is
  called, or the dedup fix silently breaks a mode that isn't even
  genealogy.** Because the dedup is applied universally (not gated on
  `genealogyMode`), it now sits alongside the existing MeritRank-mode
  `setContext()` and `togglePositiveOnly()`, both of which already call
  `graphController.clear()` (`graph_cubit.dart:137,149`) followed by a
  fresh `_fetch()`. If `_addedEdgeEndpoints` isn't cleared in the same two
  places, every edge that existed before the clear stays recorded as
  "already added" — so after switching context or toggling the filter, the
  next `_updateGraph` call finds every edge already in
  `_addedEdgeEndpoints` and skips re-adding *all* of them to the now-empty
  controller, silently leaving a graph with nodes but no edges. Add
  `_addedEdgeEndpoints.clear();` next to the existing `_fetchLimits.clear();`
  call in both methods.

- `_updateGraph`'s color selection — one conditional added ahead of the
  existing rule:

  ```dart
  final color = switch (e.branch) {
    GenealogyEdgeBranch.ego => _edgeColors.ego,
    GenealogyEdgeBranch.target => _edgeColors.target,
    GenealogyEdgeBranch.neutral => _edgeColors.neutral,
    null => e.weight < 0
        ? _edgeColors.negative
        : (src == _egoOrGenealogyEgoNode || dst == _egoOrGenealogyEgoNode)
            ? _edgeColors.ego
            : _edgeColors.neutral,
  };
  ```

  (`_egoOrGenealogyEgoNode` — resolve `_nodes[state.egoNodeId]` when
  `genealogyMode`, else `_egoNode`, computed once per call.)

- `togglePositiveOnly()` / `setContext()`: early-return when `genealogyMode`
  is true, same pattern as the existing `forwardsGraphBeaconId != null`
  guards.

*(Optional, not required for correctness: track a `_genealogyExhausted:
Set<String>` of node keys whose last page came back shorter than
`kFetchWindowSize`, and skip re-fetching them on repeat taps. Nice-to-have
for avoiding a pointless network round trip when a user re-taps an
already-fully-expanded node; leave for a follow-up if it doesn't fall out
naturally during implementation.)*

### 3.3 `GraphBody` (`packages/client/lib/features/graph/ui/widget/graph_body.dart`)

One-line change to the `withRating` computation. Note this is an intentional
behavior change from the current standalone widget, which passes
`withRating: false` today — showing rating gauges and mutual-friend badges on
genealogy nodes is explicitly what was asked for, not an incidental side
effect of the reuse:

```dart
nodeBuilder: (_, node) => GraphNodeWidget(
  key: ValueKey(node),
  nodeDetails: node,
  withRating: node is GenealogyUserNode
      ? true
      : graphNodeShowsMeritRankRating(nodeId: node.id, viewerId: _graphCubit.state.me.id),
  onTap: () => _onNodeTap(node),
),
```

Everything else (double-tap → profile, tap-once → focus/expand, labels) is
already correctly wired for `GenealogyUserNode` / `GenealogyDeletedNode` —
confirmed by reading the current source, no further changes needed here.

### 3.4 `_GraphSideControls`

Hide the "hide negative" filter toggle in genealogy mode — gate
`showFilterToggle` on `!cubit.genealogyMode` in addition to the existing
`windowClass == WindowClass.expanded` check.

## Part 4 — Screen wiring, and retiring the old widget

### 4.1 `InviteGenealogyScreen` (`packages/client/lib/features/invite_genealogy/ui/screen/invite_genealogy_screen.dart`)

Replace the `InviteGenealogyGraphCubit` + `InviteGenealogyGraphBody` wiring
with `GraphCubit` + `GraphBody`, following `forwards_graph_screen.dart`'s
established pattern:

```dart
create: (context) => GraphCubit(
  me: GetIt.I<ProfileCubit>().state.profile,
  graphSourceRepository: GetIt.I<InviteGenealogyRepository>(),
  genealogyMode: true,
  genealogyTargetId: (targetId?.isEmpty ?? true) ? null : targetId,
  genealogyAnonymousNodeLabel: l10n.inviteGenealogyAnonymousNode,
  edgeColors: GraphEdgeColors.fromTokens(context.ttOnce),
),
...
body: const TenturaFullBleed(child: GraphBody()),
```

### 4.2 Delete the standalone genealogy cubit/state/widget only

Once §4.1 is live and verified, delete `invite_genealogy_graph_cubit.dart`,
`invite_genealogy_graph_state.dart` (+ `.freezed.dart`), and
`invite_genealogy_graph_body.dart`.

**Do not delete** `invite_genealogy_fetch.graphql` /
`invite_genealogy_between_fetch.graphql` or their generated code — the
renamed `fetchGenealogyBootstrap` (§2.2) still issues exactly these two
queries unchanged. There is nothing to delete on the bootstrap path; the only
new GraphQL surface is the children query added in §2.1.

## Part 5 — Rollout sequencing

**Server before client, always**, for this feature specifically — we just
hit a live incident (`inviteGenealogyBetween` field-not-found error) caused
by the client shipping a query before the server finished deploying the
matching resolver. Land and deploy Part 1 (server) as its own PR/deploy
first, confirm the new field is live (`__type(name: "Query")` introspection,
as done during triage), *then* ship the client changes — and double-check the
V2 routing allowlist entry (§2.1) is in the same client deploy as the new
query, since a query present in the schema but missing from
`_tenturaDirectOperationNames` fails the same way (routed to Hasura, which
doesn't have it) even once the server is fully deployed.

**Accepted old-client gap during the rollout window:** the moment Part 1
(server) deploys, `fetchLineage` starts returning ancestors-only for
*every* client still running the old build — including native clients that
haven't picked up the new release yet — with no child-expansion query
available to them at all until they update. This is a real, temporary loss
of already-shipped functionality (seeing descendants on your own profile),
not just a new-feature gap. It degrades gracefully (fewer nodes shown, no
crash — unlike the field-not-found failure mode this plan is trying to avoid
elsewhere), and since client + server build in the same CI pipeline and
typically deploy close together, the window should be short. Explicitly
accepting this tradeoff here rather than discovering it as a surprise;
revisit only if old-client deploy lag turns out to be longer than expected
in practice.

## Part 6 — Test plan (expanded)

Server (§1.9 above) plus client:

- `InviteGenealogyRepository`: `fetchChildren` cursor pagination (feeding the
  previous page's last edge back in as the cursor yields the next slice,
  fixed limit, empty page at the end), and confirm calling the
  `GraphSourceRepository` marker `fetch()` adapter throws `UnsupportedError`
  rather than being silently exercised by `GraphCubit`'s genealogy branch (it
  should never be called when `genealogyMode` is true).
- `GraphCubit` (genealogy mode):
  - Isolated viewer node (no ancestors) renders correctly — the
    `graph.nodes`-with-empty-`edges` case from §2.2's "hard invariant" note.
  - Isolated target node in "between" mode, same case on the other endpoint.
  - Root-of-chain ancestor node (the one that's never a `dst`) is present in
    the rendered graph — this is the regression test for reason 3 above; rev
    1 of this plan would have failed it.
  - Tapping a node twice in succession (outside the double-tap window)
    advances `_genealogyChildrenCursors` and yields a second, non-overlapping
    page, not a repeat of the first.
  - Bootstrap draws `grandparent → parent` with a branch color, then tapping
    `grandparent` to expand its children must **not** produce a second,
    differently-colored edge between the same two nodes — the regression
    test for the dedup fix above.
  - No synthetic ego `UserNode` is ever added to the controller in
    `genealogyMode`.
  - "Between" mode: edges on the viewer's branch, target's branch, and the
    shared trunk get `GraphEdgeColors.ego` / `.target` / `.neutral`
    respectively.
  - `togglePositiveOnly()` / `setContext()` are no-ops in genealogy mode.
- `GraphCubit` (MeritRank mode, regression coverage for the now-universal
  dedup set): calling `togglePositiveOnly()` or `setContext()` after edges
  have already been added must result in those same edges being redrawn
  after the next fetch, not silently dropped — the regression test for the
  `_addedEdgeEndpoints.clear()` fix.
- `GraphBody`: filter-toggle side control is absent when `genealogyMode` is
  true; `withRating` is `true` for `GenealogyUserNode` regardless of
  ego-comparison.

Existing tests for the soon-to-be-deleted `InviteGenealogyGraphCubit` /
`InviteGenealogyGraphBody` should be ported to the above rather than simply
deleted where they cover behavior (LCA branch coloring, deleted-node
rendering) that has no other test coverage post-migration.

## Explicit non-goals (raise if scope creeps here)

- No upward/ancestor pagination — not needed, ancestors are O(depth) and
  always returned in full.
- No subtree-ownership ACL on `inviteGenealogyChildren` — the server accepts
  any well-formed `node_key` from any authenticated caller, whether or not
  that node was ever visible to that specific client; the only real barrier
  is that node keys are opaque and unguessable, not a server-side check
  tying the requested key to the caller's own position in the tree. Matches
  the trust graph's existing exposure model. If this needs tightening later,
  it's a separate, larger design (would need to bound expansion to the
  caller's own ancestor/descendant closure, checked per-call).
- No change to `fetchLineageBetween`'s "walk both endpoints to the root"
  behavior — it already returns more than "path to LCA" and that's fine,
  it's cheap.
- No "exhausted node" tracking to suppress redundant re-fetch taps — nice to
  have, not required for correctness (see the optional note in §3.2).

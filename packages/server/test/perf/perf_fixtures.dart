import 'package:postgres/postgres.dart';

/// Users in `[0, visibleUsers)` get id `Upf<n>`; user 0 is the viewer.
String _userId(int n) => 'Upf${n.toString().padLeft(9, '0')}';

/// What [PerfFixture.seed] created.
final class PerfFixtureSeed {
  const PerfFixtureSeed({required this.viewerId, required this.peerIds});

  final String viewerId;
  final List<String> peerIds;
}

/// A synthetic trust field: the viewer and `visibleUsers - 1` peers who all
/// trust each other reciprocally with the viewer.
final class PerfFixture {
  /// Sparse trust: besides the viewer's own edges, each peer is linked
  /// reciprocally only to the next peer on a ring.
  const PerfFixture.sparseTrust({required this.visibleUsers})
    : _dense = false;

  /// Dense trust: every ordered pair of visible users is linked.
  const PerfFixture.denseTrust({required this.visibleUsers}) : _dense = true;

  final int visibleUsers;

  final bool _dense;

  String get name => 'v${visibleUsers}_${_dense ? 'dense' : 'sparse'}';

  /// Inserts the users and puts the trust edges into MeritRank, which is where
  /// visibility reads them from. Needs the `pgmer2` extension on [writer].
  ///
  /// MeritRank is one service shared by every database, so the graph is reset
  /// first: edges left by an earlier fixture would otherwise be timed too.
  Future<PerfFixtureSeed> seed(Connection writer) async {
    if (visibleUsers < 3) {
      throw ArgumentError.value(visibleUsers, 'visibleUsers', 'must be >= 3');
    }
    await writer.execute('SELECT mr_reset()');
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
SELECT 'Upf' || lpad(n::text, 9, '0'), 'perf ' || n, 'pk-perf-' || n
FROM generate_series(0, @count::int - 1) n
'''),
      parameters: {'count': visibleUsers},
    );
    if (_dense) {
      await _putDenseEdges(writer);
    } else {
      await _putSparseEdges(writer);
    }
    return PerfFixtureSeed(
      viewerId: _userId(0),
      peerIds: [for (var n = 1; n < visibleUsers; n++) _userId(n)],
    );
  }

  /// Replaces the MeritRank graph with this fixture's edges again, which
  /// also empties MeritRank's peer-frame cache: the next visibility read is
  /// cold. The users must already exist.
  Future<void> reloadMeritRankGraph(Connection writer) async {
    await writer.execute('SELECT mr_reset()');
    if (_dense) {
      await _putDenseEdges(writer);
    } else {
      await _putSparseEdges(writer);
    }
  }

  /// A million `mr_put_edge` RPCs would dominate the run, so the complete
  /// graph goes in with one `mr_bulk_load_edges`, which replaces the graph it
  /// is given rather than adding to it.
  Future<void> _putDenseEdges(Connection writer) => writer.execute(
    Sql.named('''
SELECT mr_bulk_load_edges(
  array_agg(e.src), array_agg(e.dst),
  array_agg(0.75::double precision), array_agg(0::bigint),
  array_agg(''::text), 120000::bigint)
FROM (
  SELECT 'Upf' || lpad(a::text, 9, '0') AS src,
         'Upf' || lpad(b::text, 9, '0') AS dst
  FROM generate_series(0, @count::int - 1) a,
       generate_series(0, @count::int - 1) b
  WHERE a <> b
) e
'''),
    parameters: {'count': visibleUsers},
  );

  Future<void> _putSparseEdges(Connection writer) async {
    await writer.execute(
      Sql.named('''
SELECT mr_put_edge(e.src, e.dst, 0.75::double precision, ''::text, 0)
FROM (
  SELECT v.id AS src, p.id AS dst FROM
    (SELECT 'Upf' || lpad('0', 9, '0') AS id) v,
    (SELECT 'Upf' || lpad(n::text, 9, '0') AS id
     FROM generate_series(1, @count::int - 1) n) p
  UNION ALL
  SELECT p.id, v.id FROM
    (SELECT 'Upf' || lpad('0', 9, '0') AS id) v,
    (SELECT 'Upf' || lpad(n::text, 9, '0') AS id
     FROM generate_series(1, @count::int - 1) n) p
  UNION ALL
  SELECT 'Upf' || lpad(n::text, 9, '0'),
         'Upf' || lpad((n % (@count::int - 1) + 1)::text, 9, '0')
  FROM generate_series(1, @count::int - 1) n
  UNION ALL
  SELECT 'Upf' || lpad((n % (@count::int - 1) + 1)::text, 9, '0'),
         'Upf' || lpad(n::text, 9, '0')
  FROM generate_series(1, @count::int - 1) n
) e
'''),
      parameters: {'count': visibleUsers},
    );
  }
}

/// MeritRank starts empty until `meritrank_init()` or the first edge, and a
/// MeritRank-dependent timing over an empty graph measures nothing.
Future<void> requireNonEmptyMeritRankGraph(Connection connection) async {
  final edges =
      (await connection.execute(
            'SELECT count(*)::int FROM mr_edgelist()',
          )).first.first!
          as int;
  if (edges == 0) {
    throw StateError(
      'mr_edgelist() is empty: the MeritRank graph was not loaded for this '
      'database, so MeritRank-dependent timings would be meaningless',
    );
  }
}

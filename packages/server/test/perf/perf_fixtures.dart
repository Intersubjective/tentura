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
  const PerfFixture.sparseTrust({required this.visibleUsers});

  final int visibleUsers;

  String get name => 'v${visibleUsers}_sparse';

  /// Inserts the users and puts the trust edges into MeritRank, which is where
  /// visibility reads them from. Needs the `pgmer2` extension on [writer].
  Future<PerfFixtureSeed> seed(Connection writer) async {
    if (visibleUsers < 3) {
      throw ArgumentError.value(visibleUsers, 'visibleUsers', 'must be >= 3');
    }
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
SELECT 'Upf' || lpad(n::text, 9, '0'), 'perf ' || n, 'pk-perf-' || n
FROM generate_series(0, @count::int - 1) n
'''),
      parameters: {'count': visibleUsers},
    );
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
    return PerfFixtureSeed(
      viewerId: _userId(0),
      peerIds: [for (var n = 1; n < visibleUsers; n++) _userId(n)],
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

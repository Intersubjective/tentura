// `perf` suites are timing-sensitive, so like `mr` suites they run serialised
// (`-j 1`) and outside the default and plain-`pg` runs.
@Tags(['perf', 'pg', 'mr'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../support/disposable_pg_target.dart';
import 'perf_fixtures.dart';

/// Dense trust seeds a complete reciprocal graph over the visible users, so
/// the MeritRank edge count is what separates it from the sparse ring fixture.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERF_DENSE_TRUST_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_perf_dense',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for perf fixture test';

  for (final visibleUsers in [100, 300]) {
    final fixtureSpec = PerfFixture.denseTrust(visibleUsers: visibleUsers);

    group('dense-trust perf fixture with $visibleUsers visible users', () {
      late DisposablePgWriterSession session;
      late PerfFixtureSeed seed;

      setUpAll(() async {
        if (skipReason != false) return;
        session = await setUpDisposablePgWriter(
          target: target,
          createPgmer2Extension: true,
        );
        seed = await fixtureSpec.seed(session.writer);
        await requireNonEmptyMeritRankGraph(session.writer);
      });

      tearDownAll(() async {
        if (skipReason != false) return;
        await tearDownDisposablePgWriter(session: session);
      });

      test('is named after its size and density', () {
        expect(fixtureSpec.name, 'v${visibleUsers}_dense');
      });

      test('creates the viewer and every peer as users', () async {
        final users =
            (await session.writer.execute(
                  Sql.named(
                    'SELECT count(*)::int FROM public."user" '
                    "WHERE id LIKE 'Upf%'",
                  ),
                )).first.first!
                as int;

        expect(users, visibleUsers);
        expect(seed.peerIds, hasLength(visibleUsers - 1));
      });

      test('links every ordered pair of visible users in MeritRank', () async {
        final ids = [seed.viewerId, ...seed.peerIds];
        final edges =
            (await session.writer.execute(
                  Sql.named('''
SELECT count(*)::int FROM mr_edgelist() e
WHERE e.src = ANY(@ids::text[]) AND e.dst = ANY(@ids::text[])
'''),
                  parameters: {'ids': ids},
                )).first.first!
                as int;

        expect(edges, visibleUsers * (visibleUsers - 1));
      });
    }, skip: skipReason);
  }
}

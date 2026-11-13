@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../support/disposable_pg_target.dart';
import '../support/pg_test_public_keys.dart';

/// The generated Drift table class exposes the origin columns of a fact copied
/// from another fact, and reads null for an ordinary fact.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_ORIGIN_DRIFT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_origin_drift',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('beacon_fact_cards Drift origin columns', () {
    late DisposablePgWriterSession session;
    late TenturaDb db;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        final w = session.writer;
        await w.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('Udrift000001', 'u', @key)
'''),
          parameters: {'key': pgTestPublicKey('factdrift', 1)},
        );
        await w.execute(
          Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable)
VALUES ('Bdrift000001', 'Udrift000001', 't', 'd', 0, now(), false)
'''),
        );
        await w.execute(
          Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status,
   origin_fact_card_id, origin_revision_seq, origin_beacon_kind)
VALUES ('Fdriftcopy01', 'Bdrift000001', 'copy', 0, 'Udrift000001', 0,
        'Fdriftsrc001', 4, 1)
'''),
        );
        await w.execute(
          Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status)
VALUES ('Fdriftplain1', 'Bdrift000001', 'plain', 0, 'Udrift000001', 0)
'''),
        );
        db = TenturaDb.forTest(
          database: PgDatabase.opened(
            Pool<dynamic>.withEndpoints(
              [target.databaseEnv.pgEndpoint],
              settings: target.databaseEnv.pgPoolSettings,
            ),
            enableMigrations: false,
          ),
        );
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    test(
      'a copy reads back its origin fact id, revision seq and beacon kind',
      () async {
        final rows = await db.select(db.beaconFactCards).get();
        final copy = rows.firstWhere((r) => r.id == 'Fdriftcopy01');
        expect(copy.originFactCardId, 'Fdriftsrc001');
        expect(copy.originRevisionSeq, 4);
        expect(copy.originBeaconKind, 1);
      },
      skip: skipReason,
    );

    test(
      'an ordinary fact reads back null origin columns',
      () async {
        final rows = await db.select(db.beaconFactCards).get();
        final plain = rows.firstWhere((r) => r.id == 'Fdriftplain1');
        expect(plain.originFactCardId, isNull);
        expect(plain.originRevisionSeq, isNull);
        expect(plain.originBeaconKind, isNull);
      },
      skip: skipReason,
    );
  });
}

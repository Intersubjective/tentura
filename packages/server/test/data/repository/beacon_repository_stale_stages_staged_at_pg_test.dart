@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Ub043author1';
const _beacon = 'Bb043stage01';
const _stagedImage = '00000000-0000-4000-8000-0000000043a1';
final _stagedAt = DateTime.utc(2019, 6, 15, 12, 30, 45);

/// Stage-expiry reads `staged_at` through a raw `customSelect`. Drift may
/// return `DateTime` or text, not `PgDateTime`; `row.read<PgDateTime>` then
/// fails with “Could not find a matching SQL type for PgDateTime”.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_STALE_STAGES_STAGED_AT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_beacon_stale_stages_staged_at',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('BeaconRepository.staleStages decodes staged_at', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late BeaconRepository beacons;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      beacons = BeaconRepository(database);
    });

    setUp(() => _seed(writer));

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    test('returns candidates with stagedAt read from the row', () async {
      final rows = await beacons.staleStages(
        olderThan: DateTime.utc(2020),
        limit: 10,
      );

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.beaconId, _beacon);
      expect(row.imageId, _stagedImage);
      expect(row.authorId, _author);
      expect(row.stagedAt.toUtc(), _stagedAt);
    });
  });
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.beacon_image_stage,
  public.beacon_image,
  public.beacon,
  public.image,
  public."user"
CASCADE
''');
  await writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
    parameters: {'id': _author, 'key': pgTestPublicKey('b043', 1)},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, is_discoverable, published_at)
VALUES (@id, @author, 'Stage expiry', 'Sweep', 0, false, now())
'''),
    parameters: {'id': _beacon, 'author': _author},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.image (id, hash, height, width, author_id)
VALUES (@id::uuid, @hash, 48, 64, @author)
'''),
    parameters: {
      'id': _stagedImage,
      'hash': 'h$_stagedImage',
      'author': _author,
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_image_stage (image_id, beacon_id, staged_at)
VALUES (@image::uuid, @beacon, @staged_at)
'''),
    parameters: {
      'image': _stagedImage,
      'beacon': _beacon,
      'staged_at': _stagedAt,
    },
  );
}

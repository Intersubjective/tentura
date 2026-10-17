@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Ub006author1';
const _beacon = 'Bb006thumb01';
const _cover = '00000000-0000-4000-8000-00000000b061';
const _thumb = '00000000-0000-4000-8000-00000000b062';

/// B006 (#341): `replaceMedia` must keep a staged cover thumbnail it promotes.
/// Before the fix it returned the thumb for garbage collection, the caller
/// deleted its `image` row, and the `ON DELETE SET NULL` FK silently cleared
/// `beacon.cover_thumb_image_id`; the next autosave then failed with 1306.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REPLACE_MEDIA_COVER_THUMB_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_replace_media_cover_thumb',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('BeaconRepository.replaceMedia with a staged cover thumbnail', () {
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

    Future<List<String>> save() => beacons.replaceMedia(
      beaconId: _beacon,
      imageIds: const [_cover],
      coverImageId: _cover,
      coverSource: BeaconCoverSource.photo,
      coverThumbImageId: _thumb,
    );

    test('keeps the thumb, its image row and the beacon link', () async {
      final removed = await save();

      expect(removed, isNot(contains(_thumb)));
      expect(await _thumbOf(writer), _thumb);
      expect(await _imageExists(writer, _thumb), isTrue);
      expect(await _isStaged(writer, _thumb), isFalse);
    });

    test('a repeat save with the same thumb collects nothing', () async {
      await save();

      expect(await save(), isEmpty);
      expect(await _thumbOf(writer), _thumb);
      expect(await _imageExists(writer, _thumb), isTrue);
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
    parameters: {'id': _author, 'key': pgTestPublicKey('b006', 1)},
  );
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, is_discoverable, published_at)
VALUES ('$_beacon', '$_author', 'Move the piano', 'Saturday', 0, false, now())
''');
  for (final id in [_cover, _thumb]) {
    await writer.execute(
      Sql.named(
        'INSERT INTO public.image (id, hash, height, width, author_id) '
        'VALUES (@id::uuid, @hash, 48, 64, @author)',
      ),
      parameters: {'id': id, 'hash': 'h$id', 'author': _author},
    );
    await writer.execute(
      Sql.named(
        'INSERT INTO public.beacon_image_stage (image_id, beacon_id) '
        'VALUES (@id::uuid, @beacon)',
      ),
      parameters: {'id': id, 'beacon': _beacon},
    );
  }
}

Future<String?> _thumbOf(Connection writer) async {
  final row = (await writer.execute(
    Sql.named(
      'SELECT cover_thumb_image_id::text FROM public.beacon WHERE id = @id',
    ),
    parameters: {'id': _beacon},
  )).single;
  return row[0] as String?;
}

Future<bool> _imageExists(Connection writer, String id) async =>
    (await writer.execute(
      Sql.named('SELECT 1 FROM public.image WHERE id = @id::uuid'),
      parameters: {'id': id},
    )).isNotEmpty;

Future<bool> _isStaged(Connection writer, String id) async =>
    (await writer.execute(
      Sql.named(
        'SELECT 1 FROM public.beacon_image_stage WHERE image_id = @id::uuid',
      ),
      parameters: {'id': id},
    )).isNotEmpty;

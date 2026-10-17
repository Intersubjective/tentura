@Tags(['pg'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';

import '../../support/disposable_pg_target.dart';

/// U090 — a status change leaves a line in the Request's discussion, so a
/// member coming back sees what changed instead of a header that silently
/// says something else. Kind 7 (`statusChanged`) system line; author is the
/// actor (null for automatic changes); payload `{version, fromStatus,
/// toStatus, reason}`.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_STATUS_ROOM_LINE_TEST_DB',
    defaultNamePrefix: 'tentura_test_status_room_line',
  );
  final skipReason = await pgSkipReason(target);

  const authorId = 'Ustatusauth1';
  const beaconId = 'Bstatusline1';
  const postId = 'Bstatuspost1';

  group('recordBeaconStatusTransition posts a room line (U090)', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late BeaconRepository beacons;

    Future<List<Map<String, Object?>>> statusLines(String id) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT author_id, system_message_kind, system_payload::text '
          'FROM public.beacon_room_message '
          'WHERE beacon_id = @id AND system_message_kind IS NOT NULL '
          'ORDER BY created_at, id',
        ),
        parameters: {'id': id},
      );
      return [
        for (final r in rows)
          {
            'author': r[0],
            'kind': r[1],
            'payload': jsonDecode(r[2]! as String),
          },
      ];
    }

    Future<void> insertBeacon(String id, {required int kind}) {
      // A Post carries no title/description and is never discoverable
      // (beacon_post_shape_ck).
      final isPost = kind == 1;
      final title = isPost ? '' : 'Moving day';
      final description = isPost ? '' : 'desc';
      return writer.execute(
        'INSERT INTO public.beacon (id, user_id, title, description, '
        'status, kind, is_discoverable, published_at, created_at, '
        "updated_at) VALUES ('$id', '$authorId', '$title', '$description', "
        "0, $kind, ${!isPost}, '2026-01-01T00:00:00Z', "
        "'2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
      );
    }

    setUpAll(() async {
      if (skipReason != null) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      db = TenturaDb(target.databaseEnv);
      beacons = BeaconRepository(db);
    });

    tearDownAll(() async {
      if (skipReason != null) return;
      await db.close();
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      if (skipReason != null) return;
      await writer.execute(
        'TRUNCATE TABLE public.beacon_room_message, public.beacon, '
        'public."user" CASCADE',
      );
      await writer.execute(
        'INSERT INTO public."user" (id, display_name, public_key) '
        "VALUES ('$authorId', 'Author', 'key-$authorId')",
      );
      await insertBeacon(beaconId, kind: 0);
    });

    test('author marks Enough help: one line naming both statuses', () async {
      await beacons.recordBeaconStatusTransition(
        beaconId: beaconId,
        fromStatus: BeaconStatus.open,
        toStatus: BeaconStatus.enoughHelp,
        reason: BeaconLifecycleChangeReason.enoughHelp,
        actorId: authorId,
      );
      final lines = await statusLines(beaconId);
      expect(lines, hasLength(1));
      expect(lines.single['author'], authorId);
      expect(lines.single['kind'], 7);
      expect(lines.single['payload'], {
        'version': 1,
        'fromStatus': BeaconStatus.open.smallintValue,
        'toStatus': BeaconStatus.enoughHelp.smallintValue,
        'reason': BeaconLifecycleChangeReason.enoughHelp,
      });
    });

    test('an automatic change (no actor) still leaves a line', () async {
      await beacons.recordBeaconStatusTransition(
        beaconId: beaconId,
        fromStatus: BeaconStatus.reviewOpen,
        toStatus: BeaconStatus.closed,
        reason: BeaconLifecycleChangeReason.closureExpired,
        actorId: null,
      );
      final lines = await statusLines(beaconId);
      expect(lines, hasLength(1));
      expect(lines.single['author'], isNull);
    });

    test('a deletion leaves no line', () async {
      await beacons.recordBeaconStatusTransition(
        beaconId: beaconId,
        fromStatus: BeaconStatus.open,
        toStatus: BeaconStatus.deleted,
        reason: BeaconLifecycleChangeReason.deleted,
        actorId: authorId,
      );
      expect(await statusLines(beaconId), isEmpty);
    });

    test('Posts are left alone (they have their own closed notice)', () async {
      await insertBeacon(postId, kind: 1);
      await beacons.recordBeaconStatusTransition(
        beaconId: postId,
        fromStatus: BeaconStatus.open,
        toStatus: BeaconStatus.closed,
        reason: BeaconLifecycleChangeReason.directClose,
        actorId: authorId,
      );
      expect(await statusLines(postId), isEmpty);
    });
  }, skip: skipReason ?? false);
}

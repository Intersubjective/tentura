@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/closure_reminder_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

import '../../support/disposable_pg_target.dart';

/// Request-only SQL: a Post (`beacon.kind = 1`) shares its author with a
/// Request but must not show up in responsibility scope, the constellation
/// Request sections (own, discoverable, snapshot), deadline reminders,
/// stale-request reminders, or trigger a before-response tombstone when
/// deleted.
/// See `docs/plans/post-and-constellation-composer-plan.md`.
const _author = 'Um0213author01';
const _viewer = 'Um0213viewer001';
const _request = 'Bm0213request01';
const _post = 'Bm0213post00001';

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0213_REQUEST_ONLY_SQL_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0213_reqonly_mig',
  );
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0213_REQUEST_ONLY_SQL_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0213_reqonly',
  );
  final pgSkip =
      await pgSkipReason(migrationTarget) ?? await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('upgrade from the previous schema version', () {
    late DisposablePgWriterSession session;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: migrationTarget,
        lastInclusiveVersion: '0212',
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('after migrating, responsibility scope skips the Post and '
        'deleting it creates no tombstone', () async {
      final writer = session.writer;
      await _seedUsers(writer);
      await _insertRequest(writer);
      await _insertPost(writer, requestLike: false);
      await _insertInboxItems(writer);

      await migrateDbSchema(writer);

      expect(await _responsibilityScope(writer), {_request});
      await writer.execute(
        "UPDATE public.beacon SET status = 2 WHERE id IN ('$_request', '$_post')",
      );
      final tombstones = await _inboxTombstones(writer);
      expect(tombstones[_request], 4);
      expect(tombstones[_post], 0);
    });
  });

  group('full schema', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      // The Post shape check would keep Request-only columns (`end_at`,
      // `is_discoverable`, title) off a Post, which hides whether the SQL
      // filters on `kind`. Drop it in this disposable database only.
      await writer.execute(
        'ALTER TABLE public.beacon DROP CONSTRAINT beacon_post_shape_ck',
      );
    });

    setUp(() async {
      await _seedUsers(writer);
      await _insertRequest(writer);
      await _insertPost(writer, requestLike: true);
      await _insertInboxItems(writer);
      await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES ('$_author', '$_viewer', 1), ('$_viewer', '$_author', 1)
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');
    });

    tearDown(() async {
      await writer.execute('DELETE FROM public.vote_user '
          "WHERE subject IN ('$_author', '$_viewer')");
      await writer.execute(
        "DELETE FROM public.notification_outbox WHERE beacon_id LIKE 'Bm0213%'",
      );
      await writer.execute(
        "DELETE FROM public.inbox_item WHERE beacon_id LIKE 'Bm0213%'",
      );
      await writer.execute("DELETE FROM public.beacon WHERE id LIKE 'Bm0213%'");
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    ConstellationFieldRepository constellation() =>
        ConstellationFieldRepository(database, _NoProfiles());

    test('responsibility scope lists the Request but not the Post', () async {
      final ids = await _responsibilityScope(writer);
      expect(ids, contains(_request));
      expect(ids, isNot(contains(_post)));
    });

    test('own-requests section lists the Request but not the Post', () async {
      final records = await constellation().ownRequests(viewerId: _author);
      final ids = records.map((r) => r.id).toSet();
      expect(ids, contains(_request));
      expect(ids, isNot(contains(_post)));
    });

    test('discoverable-requests section lists the Request but not the '
        'Post', () async {
      final records = await constellation().discoverableRequests(
        viewerId: _viewer,
        context: '',
        cap: 50,
      );
      final ids = records.map((r) => r.id).toSet();
      expect(ids, contains(_request));
      expect(ids, isNot(contains(_post)));
    });

    test('field snapshot requests list the Request but not the Post, for the '
        'author and for a viewer', () async {
      for (final viewer in [_author, _viewer]) {
        final snapshot = await constellation().readSnapshot(
          viewerId: viewer,
          context: '',
          params: (
            filters: ConstellationFieldMembershipFilters.defaults,
            projection: ConstellationProjection.full,
          ),
        );
        final ids = snapshot.requests.map((r) => r.id).toSet();
        expect(ids, contains(_request), reason: 'viewer $viewer');
        expect(ids, isNot(contains(_post)), reason: 'viewer $viewer');
      }
    });

    test('stale-request reminders are written for the Request but not the '
        'Post', () async {
      await ClosureReminderRepository(database).writeStaleRequestReminders(
        now: DateTime.now().toUtc(),
        weekKey: '2026-W40',
      );
      final rows = await writer.execute('''
SELECT beacon_id FROM public.notification_outbox
WHERE beacon_id LIKE 'Bm0213%' AND source_event_key LIKE 'stale_request:%'
''');
      final ids = rows.map((r) => r[0]! as String).toSet();
      expect(ids, contains(_request));
      expect(ids, isNot(contains(_post)));
    });

    test('deadline reminder candidates and lock include the Request but not '
        'the Post', () async {
      final today = DateTime.now().toUtc();
      final dayStart = DateTime.utc(today.year, today.month, today.day);
      final next = dayStart.add(const Duration(days: 1));
      final following = dayStart.add(const Duration(days: 2));
      final repository = BeaconRepository(database);

      final ids = await repository.deadlineReminderCandidateIds(
        nextUtcDayStart: next,
        followingUtcDayStart: following,
      );
      expect(ids, contains(_request));
      expect(ids, isNot(contains(_post)));

      final lockedRequest = await repository.lockOpenBeaconForDeadlineReminder(
        beaconId: _request,
        nextUtcDayStart: next,
        followingUtcDayStart: following,
      );
      expect(lockedRequest?.id, _request);

      final lockedPost = await repository.lockOpenBeaconForDeadlineReminder(
        beaconId: _post,
        nextUtcDayStart: next,
        followingUtcDayStart: following,
      );
      expect(lockedPost, isNull);
    });

    test('deleting a Request tombstones its inbox items, deleting a Post '
        'does not', () async {
      final repository = BeaconRepository(database);
      for (final id in [_request, _post]) {
        await repository.recordBeaconStatusTransition(
          beaconId: id,
          fromStatus: BeaconStatus.open,
          toStatus: BeaconStatus.deleted,
          reason: BeaconLifecycleChangeReason.deleted,
          actorId: _author,
        );
      }
      final tombstones = await _inboxTombstones(writer);
      expect(tombstones[_request], 4);
      expect(tombstones[_post], 0);
      final stamped = await writer.execute('''
SELECT beacon_id FROM public.inbox_item
WHERE beacon_id LIKE 'Bm0213%' AND before_response_terminal_at IS NOT NULL
''');
      expect(stamped.map((r) => r[0]), [_request]);
    });
  });
}

Future<void> _seedUsers(Connection writer) async {
  for (final id in [_author, _viewer]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id') ON CONFLICT DO NOTHING
''');
  }
}

Future<void> _insertRequest(Connection writer) => writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at, created_at,
   status_changed_at, end_at, is_discoverable)
VALUES ('$_request', '$_author', 'Request', 'd', 0, 0,
  now() - interval '60 days', now() - interval '60 days',
  now() - interval '60 days',
  date_trunc('day', now()) + interval '1 day 6 hours', true)
''');

/// [requestLike] gives the Post the Request-only columns (`end_at`,
/// `is_discoverable`, title); that needs the shape check dropped.
Future<void> _insertPost(Connection writer, {required bool requestLike}) =>
    writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at, created_at,
   status_changed_at, end_at, is_discoverable)
VALUES ('$_post', '$_author', '${requestLike ? 'Post' : ''}', '', 0, 1,
  now() - interval '60 days', now() - interval '60 days',
  now() - interval '60 days',
  ${requestLike ? "date_trunc('day', now()) + interval '1 day 6 hours'" : 'NULL'},
  $requestLike)
''');

Future<void> _insertInboxItems(Connection writer) => writer.execute('''
INSERT INTO public.inbox_item (user_id, beacon_id)
VALUES ('$_viewer', '$_request'), ('$_viewer', '$_post')
''');

Future<Set<String>> _responsibilityScope(Connection writer) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT beacon_id FROM public.responsibility_scope_base_beacons(@u)',
    ),
    parameters: {'u': _author},
  );
  return rows.map((r) => r[0]! as String).toSet();
}

Future<Map<String, int>> _inboxTombstones(Connection writer) async {
  final rows = await writer.execute('''
SELECT beacon_id, status FROM public.inbox_item WHERE beacon_id LIKE 'Bm0213%'
''');
  return {for (final r in rows) r[0]! as String: r[1]! as int};
}

final class _NoProfiles implements UserProfileBatchLookup {
  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(
    Iterable<String> ids,
  ) async => {};

  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
    Set<String> trustsViewerPeerIds = const {},
    Set<String> viewerTrustsPeerIds = const {},
    Map<String, MutualScoreRecord> scoresByPeerId = const {},
  }) async => {};
}

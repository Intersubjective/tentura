@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';
import 'package:tentura_server/domain/use_case/post_close_operation.dart';
import 'package:tentura_server/domain/use_case/post_expiry_sweep_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Uexpsweepauth01';
const _member = 'Uexpsweepmemb01';
const _users = [_author, _member];

const _expiredA = 'Bexpsweepold001';
const _expiredB = 'Bexpsweepold002';
const _future = 'Bexpsweepfut001';
const _request = 'Bexpsweepreq001';
const _child = 'Bexpsweepchd001';

/// The sweeper that closes every open Post whose lifetime ran out: only
/// Posts, only expired ones, each exactly once, and one bad row never blocks
/// the rest.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_EXPIRY_SWEEP_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_expiry_sweep',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb database;
  late Connection writer;
  late MutatingUnitOfWork uow;
  late PostCloseOperation close;
  late PostExpirySweepCase sweep;
  late _RecordingPostLock lock;
  late List<String> events;
  late List<LogRecord> severeLogs;
  late StreamSubscription<LogRecord> logSubscription;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    uow = MutatingUnitOfWork(database);
    final beacons = BeaconRepository(database);
    close = PostCloseOperation(beacons);
    final logger = Logger('PostExpirySweepPgTest');
    severeLogs = [];
    logSubscription = logger.onRecord
        .where((record) => record.level >= Level.SEVERE)
        .listen(severeLogs.add);
    events = [];
    lock = _RecordingPostLock(PostLockRepository(database), events);
    sweep = PostExpirySweepCase(
      unitOfWork: uow,
      beaconRepository: beacons,
      postLock: lock,
      postClose: close,
      env: Env(environment: Environment.test, printEnv: false),
      logger: logger,
    );
  });

  setUp(() async {
    severeLogs.clear();
    events.clear();
    lock.failFor = null;
    sweep.afterSelect = null;
    await _seed(writer);
  });

  tearDownAll(() async {
    await logSubscription.cancel();
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  Future<int> status(String beaconId) async =>
      (await writer.execute(
            "SELECT status FROM public.beacon WHERE id = '$beaconId'",
          )).single.single!
          as int;

  Future<List<Map<String, Object?>>> notices(String beaconId) async {
    final rows = await writer.execute('''
SELECT system_payload FROM public.beacon_room_message
WHERE beacon_id = '$beaconId'
  AND system_message_kind = ${BeaconRoomSystemMessageKind.postClosed}
''');
    return [for (final row in rows) _json(row.single)];
  }

  Future<List<Map<String, Object?>>> lifecycleDiffs(String beaconId) async {
    final rows = await writer.execute('''
SELECT diff FROM public.beacon_activity_event
WHERE beacon_id = '$beaconId'
  AND type = ${BeaconActivityEventTypeBits.beaconLifecycleChanged}
''');
    return [for (final row in rows) _json(row.single)];
  }

  /// Installs [race] as the between-select-and-lock hook and records when it
  /// ran relative to the per-row locks.
  void raceBetweenSelectAndLock(Future<void> Function() race) {
    sweep.afterSelect = () {
      events.add('afterSelect');
      return race();
    };
  }

  group('PostExpirySweepCase.runDue', () {
    test('closes exactly the expired open Posts, with a postExpired '
        'transition and one expired notice each', () async {
      await sweep.runDue();

      for (final id in [_expiredA, _expiredB]) {
        expect(await status(id), 6, reason: '$id closed');
        final diffs = await lifecycleDiffs(id);
        expect(diffs, hasLength(1), reason: '$id has one transition');
        expect(diffs.single['reason'], 'postExpired');
        expect(diffs.single['toStatus'], 6);
        final posted = await notices(id);
        expect(posted, hasLength(1), reason: '$id has one notice');
        expect(posted.single['reason'], 'expired');
      }
      expect(severeLogs, isEmpty);
    });

    test('leaves a Post with time left and a Request past its end date '
        'untouched', () async {
      await sweep.runDue();

      expect(await status(_future), 0);
      expect(await notices(_future), isEmpty);
      expect(await lifecycleDiffs(_future), isEmpty);
      expect(await status(_request), 0);
      expect(await notices(_request), isEmpty);
      expect(await lifecycleDiffs(_request), isEmpty);
    });

    test('a second run changes nothing', () async {
      await sweep.runDue();

      await sweep.runDue();

      for (final id in [_expiredA, _expiredB]) {
        expect(await status(id), 6);
        expect(await notices(id), hasLength(1));
        expect(await lifecycleDiffs(id), hasLength(1));
      }
      expect(await status(_future), 0);
      expect(severeLogs, isEmpty);
    });

    test('closes once a selected Post whose expiry was shortened further '
        'into the past between the candidate select and the lock', () async {
      // Shortening moves the Post to the front of the expiry order, so the
      // lock order proves the candidates were read before the shortening.
      raceBetweenSelectAndLock(
        () => writer.execute('''
UPDATE public.beacon SET expires_at = now() - interval '2 hours'
WHERE id = '$_expiredB'
'''),
      );

      await sweep.runDue();

      expect(events, ['afterSelect', 'lock:$_expiredA', 'lock:$_expiredB']);

      expect(await status(_expiredB), 6);
      final diffs = await lifecycleDiffs(_expiredB);
      expect(diffs, hasLength(1));
      expect(diffs.single['reason'], 'postExpired');
      final posted = await notices(_expiredB);
      expect(posted, hasLength(1));
      expect(posted.single['reason'], 'expired');
      expect(await status(_expiredA), 6);
      expect(severeLogs, isEmpty);
    });

    test('skips, without error, a Post that was closed by budding between '
        'the candidate select and the lock', () async {
      raceBetweenSelectAndLock(
        () => uow.run(
          actorUserId: _author,
          action: () => close.closeForBud(
            postId: _expiredA,
            childBeaconId: _child,
            title: 'Fix the fence',
            actorId: _author,
          ),
        ),
      );

      await sweep.runDue();

      // The budded Post is still locked after the race: it was a candidate
      // when selected, and was only found closed once the lock was held.
      expect(events, ['afterSelect', 'lock:$_expiredA', 'lock:$_expiredB']);

      expect(await status(_expiredA), 6);
      final posted = await notices(_expiredA);
      expect(posted, hasLength(1), reason: 'only the bud notice');
      expect(posted.single['reason'], 'budded');
      final diffs = await lifecycleDiffs(_expiredA);
      expect(diffs, hasLength(1));
      expect(diffs.single['reason'], isNot('postExpired'));
      expect(severeLogs, isEmpty, reason: 'a lost race is not an error');
      expect(await status(_expiredB), 6, reason: 'the rest of the batch ran');
      expect(await notices(_expiredB), hasLength(1));
    });

    test(
      'logs a row that fails and still closes the rest of the batch',
      () async {
        lock.failFor = _expiredA;

        await sweep.runDue();

        expect(
          await status(_expiredA),
          0,
          reason: 'the failed row rolled back',
        );
        expect(await notices(_expiredA), isEmpty);
        expect(await lifecycleDiffs(_expiredA), isEmpty);
        expect(await status(_expiredB), 6);
        expect(await notices(_expiredB), hasLength(1));
        expect(severeLogs, hasLength(1));
        expect(severeLogs.single.message, contains(_expiredA));
      },
    );
  });
}

Map<String, Object?> _json(Object? value) => switch (value) {
  final Map<String, Object?> map => map,
  final String text => jsonDecode(text) as Map<String, Object?>,
  _ => throw StateError('Not JSON: $value'),
};

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.beacon_hierarchy_deliveries,
  public.beacon_hierarchy_events,
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.inbox_item,
  public.beacon_activity_event,
  public.beacon_room_message_reaction,
  public.beacon_room_message,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  for (var i = 0; i < _users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': _users[i], 'key': pgTestPublicKey('expsweep', i + 1)},
    );
  }
  // Two open Posts that expired, the older one first.
  for (final (id, ago) in [(_expiredA, 90), (_expiredB, 30)]) {
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at)
VALUES ('$id', '$_author', '', '', 0, 1, 1, false,
        now() - interval '1 day', now() - interval '$ago minutes')
''');
    await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('F${id.substring(1)}', '$id', '$_author', '$_member')
''');
  }
  // An open Post with a day left to live.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at)
VALUES ('$_future', '$_author', '', '', 0, 1, 1, false,
        now() - interval '1 hour', now() + interval '23 hours')
''');
  // A Request whose end date has passed: Requests are not swept.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at, end_at)
VALUES ('$_request', '$_author', 'Request', '', 0, 0,
        now() - interval '2 days', now() - interval '1 day')
''');
  // The Request that buds out of the first expired Post mid-sweep.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, parent_beacon_id,
   is_discoverable, published_at)
VALUES ('$_child', '$_member', 'Fix the fence', '', 0, 0, '$_expiredA', false,
        now())
''');
}

/// Delegates to the real lock and records every acquisition, so a test can
/// tell when a race hook ran relative to the per-row locks.
final class _RecordingPostLock implements PostLockPort {
  _RecordingPostLock(this._inner, this._events);

  final PostLockPort _inner;
  final List<String> _events;

  /// Beacon id whose lock attempt fails, to exercise the per-row error path.
  String? failFor;

  @override
  Future<void> lockForPostMutation(String beaconId) async {
    _events.add('lock:$beaconId');
    if (beaconId == failFor) throw StateError('lock failed for $beaconId');
    await _inner.lockForPostMutation(beaconId);
  }
}

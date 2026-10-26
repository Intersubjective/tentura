@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/forward_attribution_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Uchgauthor001';
const _bob = 'Uchgbob000001';
const _stranger = 'Uchgstrang001';
const _users = [_author, _bob, _stranger];

const _post = 'Bchgpost00001';
const _request = 'Bchgrequest001';

const _statusOpen = 0;
const _statusClosed = 6;

/// The author of an open Post can end it early: shorten its lifetime (never
/// extend it) or close it now. Both are refused for anyone else and for a Post
/// that is no longer open.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_LIFETIME_CHANGE_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_lifetime_change',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb database;
  late _Harness harness;
  late Connection writer;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    harness = _Harness.build(database, target.databaseEnv);
  });
  setUp(() async => _seed(writer));
  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  Future<void> shorten({
    required DateTime to,
    String userId = _author,
    String beaconId = _post,
  }) => harness.posts.shorten(
    userId: userId,
    beaconId: beaconId,
    expiresAt: to,
  );

  Future<void> close({String userId = _author, String beaconId = _post}) =>
      harness.posts.close(userId: userId, beaconId: beaconId);

  DateTime inHours(num hours) => DateTime.now().toUtc().add(
    Duration(microseconds: (hours * Duration.microsecondsPerHour).round()),
  );

  Future<DateTime> expiresAt(String id) async =>
      (await writer.execute(
            "SELECT expires_at FROM public.beacon WHERE id = '$id'",
          )).single.single!
          as DateTime;

  Future<int> status(String id) async =>
      (await writer.execute(
            "SELECT status FROM public.beacon WHERE id = '$id'",
          )).single.single!
          as int;

  Future<bool> warningEligible(String id) async =>
      (await writer.execute(
            'SELECT expiry_warning_eligible FROM public.beacon '
            "WHERE id = '$id'",
          )).single.single!
          as bool;

  Future<int> count(String sql) async =>
      (await writer.execute(sql)).single.single! as int;

  Future<int> noticeCount(String id) => count('''
SELECT count(*)::int FROM public.beacon_room_message
WHERE beacon_id = '$id'
  AND system_message_kind = ${BeaconRoomSystemMessageKind.postClosed}
''');

  Future<List<ResultRow>> lifecycleEvents(String id) => writer.execute('''
SELECT diff, actor_id FROM public.beacon_activity_event
WHERE beacon_id = '$id'
  AND type = ${BeaconActivityEventTypeBits.beaconLifecycleChanged}
''');

  Future<Map<String, Object?>> onlyNoticePayload() async {
    final notices = await writer.execute('''
SELECT system_payload FROM public.beacon_room_message
WHERE beacon_id = '$_post'
  AND system_message_kind = ${BeaconRoomSystemMessageKind.postClosed}
''');
    expect(notices, hasLength(1));
    return _json(notices.single[0]);
  }

  /// Gives the Post the [status] and the end [expires] (an SQL expression),
  /// published [published] (an SQL expression, at most 72 hours before it
  /// ends).
  Future<void> setPost({
    required int status,
    required String expires,
    String published = "now() - interval '10 hours'",
  }) => writer.execute('''
UPDATE public.beacon
SET status = $status, published_at = $published, expires_at = $expires
WHERE id = '$_post'
''');

  group('PostCase.shorten', () {
    test(
      'moves the end of an open Post from 72 hours to six hours from now',
      () async {
        final target = inHours(6);

        await shorten(to: target);

        expect(
          (await expiresAt(_post)).difference(target).abs(),
          lessThan(const Duration(milliseconds: 1)),
        );
      },
    );

    test('leaves the Post open with no close notice', () async {
      await shorten(to: inHours(6));

      expect(await status(_post), _statusOpen);
      expect(await noticeCount(_post), 0);
      expect(await lifecycleEvents(_post), isEmpty);
    });

    test('leaves the expiry warning eligibility unchanged', () async {
      await shorten(to: inHours(6));
      expect(await warningEligible(_post), isTrue);

      await shorten(to: inHours(2));
      expect(await warningEligible(_post), isTrue);
    });

    test(
      'keeps a Post that was never eligible for the warning ineligible',
      () async {
        await writer.execute(
          'UPDATE public.beacon SET expiry_warning_eligible = false '
          "WHERE id = '$_post'",
        );

        await shorten(to: inHours(2));

        expect(await warningEligible(_post), isFalse);
      },
    );

    test('can shorten the same Post again', () async {
      await shorten(to: inHours(6));
      final target = inHours(2);

      await shorten(to: target);

      expect(
        (await expiresAt(_post)).difference(target).abs(),
        lessThan(const Duration(milliseconds: 1)),
      );
    });

    test('refuses a later end and leaves the column unchanged', () async {
      final before = await expiresAt(_post);

      await expectLater(
        shorten(to: before.add(const Duration(hours: 1))),
        throwsA(isA<PostLifetimeExtendException>()),
      );

      expect(await expiresAt(_post), before);
    });

    test('refuses the current end as a no-op extension', () async {
      final before = await expiresAt(_post);

      await expectLater(
        shorten(to: before),
        throwsA(isA<PostLifetimeExtendException>()),
      );

      expect(await expiresAt(_post), before);
    });

    test('refuses an end past the 72 hour cap as an extension', () async {
      final before = await expiresAt(_post);

      await expectLater(
        shorten(to: inHours(100)),
        throwsA(isA<PostLifetimeExtendException>()),
      );

      expect(await expiresAt(_post), before);
    });

    test('refuses an end in the past as an invalid lifetime', () async {
      final before = await expiresAt(_post);

      await expectLater(
        shorten(to: inHours(-1)),
        throwsA(isA<PostLifetimeInvalidException>()),
      );

      expect(await expiresAt(_post), before);
      expect(await status(_post), _statusOpen);
    });

    test('refuses a member who is not the author', () async {
      final before = await expiresAt(_post);

      await expectLater(
        shorten(to: inHours(6), userId: _bob),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(await expiresAt(_post), before);
    });

    test('refuses a stranger', () async {
      final before = await expiresAt(_post);

      await expectLater(
        shorten(to: inHours(6), userId: _stranger),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(await expiresAt(_post), before);
    });

    test('refuses a closed Post', () async {
      await setPost(
        status: _statusClosed,
        expires: "now() - interval '1 minute'",
      );
      final before = await expiresAt(_post);

      await expectLater(
        shorten(to: inHours(1)),
        throwsA(isA<PostNotOpenException>()),
      );

      expect(await expiresAt(_post), before);
    });

    test('refuses a Post that expired but has not been swept yet', () async {
      await setPost(
        status: _statusOpen,
        expires: "now() - interval '1 minute'",
      );
      final before = await expiresAt(_post);

      await expectLater(
        shorten(to: inHours(1)),
        throwsA(isA<PostNotOpenException>()),
      );

      expect(await expiresAt(_post), before);
      expect(await status(_post), _statusOpen);
    });

    test('refuses a Request', () async {
      await expectLater(
        shorten(to: inHours(1), beaconId: _request),
        throwsA(isA<PostNotOpenException>()),
      );
    });
  });

  group('PostCase.close', () {
    test('moves an open Post to closed', () async {
      await close();

      expect(await status(_post), _statusClosed);
    });

    test('logs a postClosedByAuthor transition by the author', () async {
      await close();

      final events = await lifecycleEvents(_post);
      expect(events, hasLength(1));
      final diff = _json(events.single[0]);
      expect(diff['reason'], 'postClosedByAuthor');
      expect(diff['fromStatus'], _statusOpen);
      expect(diff['toStatus'], _statusClosed);
      expect(events.single[1], _author);
    });

    test('inserts one close notice that says the author closed it', () async {
      await close();

      expect((await onlyNoticePayload())['reason'], 'closedByAuthor');
    });

    test('refuses a second close and adds no second notice', () async {
      await close();

      await expectLater(close(), throwsA(isA<PostNotOpenException>()));

      expect(await noticeCount(_post), 1);
      expect(await status(_post), _statusClosed);
    });

    test('refuses a member who is not the author', () async {
      await expectLater(
        close(userId: _bob),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(await status(_post), _statusOpen);
      expect(await noticeCount(_post), 0);
    });

    test('refuses a stranger', () async {
      await expectLater(
        close(userId: _stranger),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(await status(_post), _statusOpen);
    });

    test('refuses a Post that expired but has not been swept yet', () async {
      await setPost(
        status: _statusOpen,
        expires: "now() - interval '1 minute'",
      );

      await expectLater(close(), throwsA(isA<PostNotOpenException>()));

      expect(await status(_post), _statusOpen);
      expect(await noticeCount(_post), 0);
    });

    test('refuses a Request', () async {
      await expectLater(
        close(beaconId: _request),
        throwsA(isA<PostNotOpenException>()),
      );

      expect(await status(_request), _statusOpen);
    });

    test('leaves a closed Post that cannot be shortened afterwards', () async {
      await close();

      await expectLater(
        shorten(to: inHours(1)),
        throwsA(isA<PostNotOpenException>()),
      );
    });
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
      parameters: {'id': _users[i], 'key': pgTestPublicKey('chg', i + 1)},
    );
  }
  // An open Post published an hour ago with the full 72 hour lifetime.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at, expiry_warning_eligible)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false,
        now() - interval '1 hour', now() + interval '71 hours', true)
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Fchgauthbob001', '$_post', '$_author', '$_bob')
''');
  // An unrelated Request.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, 0, now())
''');
}

final class _Harness {
  const _Harness(this.posts, this.room);

  final PostCase posts;
  final BeaconRoomCase room;

  factory _Harness.build(TenturaDb db, Env env) {
    final logger = Logger('PostLifetimeChangePgTest');
    final uow = MutatingUnitOfWork(db);
    final attention = TransactionalAttentionCase(
      uow,
      AttentionDispatchRepository(db, logger),
    );
    final beaconRepository = BeaconRepository(db);
    final roomRepository = BeaconRoomRepository(db);
    final help = HelpOfferRepository(db);
    final commitments = CommitmentRepository(db);
    final access = BeaconAccessRepository(db);
    final blocks = UserBlockRepository(env, db);
    final hierarchy = BeaconHierarchyRepository(db);
    final intents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(
        roomRepository,
        db,
        help,
        commitments,
      ),
      UserRepository(
        env,
        db,
        _UnusedGenealogy(),
        InviteSeedPromptRepositoryMock(),
      ),
      access,
      blocks,
    );
    final commitmentQuery = CommitmentQueryCase(
      commitments,
      help,
      env: env,
      logger: logger,
    );
    final images = _UnusedImages();
    final tasks = _Tasks();
    final beacons = BeaconCase(
      beaconRepository,
      images,
      _UnusedImageGc(),
      tasks,
      commitmentQuery,
      access,
      hierarchy,
      FakeBeaconChildCreatePort(),
      BeaconLifecycleEffectsCase(
        BeaconHierarchyOutboxRepository(db),
        env: env,
        logger: logger,
      ),
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    );
    final forwards = ForwardCase(
      ForwardEdgeRepository(db),
      ForwardAttributionRepository(db),
      help,
      InboxRepository(db),
      CapabilityEvidenceRepository(db),
      beaconRepository,
      blocks,
      PersonVisibilityRepository(db),
      access,
      attentionIntents: intents,
      attention: attention,
      postLock: PostLockRepository(db),
      env: env,
      logger: logger,
    );
    final room = BeaconRoomCase(
      roomRepository,
      CoordinationItemRepository(db),
      _UnusedFactCards(),
      images,
      tasks,
      _Storage(),
      _UnusedPolling(),
      _Quota(),
      blocks,
      uow,
      hierarchy,
      const ProductionDiscussionProductPolicy(),
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    );
    return _Harness(
      PostCase(
        beaconCase: beacons,
        forwardCase: forwards,
        roomCase: room,
        beaconRepository: beaconRepository,
        postLock: PostLockRepository(db),
        attention: attention,
      ),
      room,
    );
  }
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedImageGc extends Fake implements ImageObjectGcPort {}

final class _UnusedFactCards extends Fake
    implements BeaconFactCardRepositoryPort {}

final class _UnusedPolling extends Fake implements PollingRepositoryPort {}

final class _Tasks extends Fake implements TaskRepositoryPort {
  @override
  Future<String> schedule(TaskEntity task) async => 'task-id';
}

final class _Storage extends Fake implements RemoteStoragePort {
  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    await bytes.drain<void>();
    return path;
  }
}

final class _Quota extends Fake implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async => true;
}

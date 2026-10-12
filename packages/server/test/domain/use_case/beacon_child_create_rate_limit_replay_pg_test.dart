@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_command_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/post_bud_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_command_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_child_create_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// Creation rate limiting versus command replay for child Requests: the
/// limit gates new commands only, so retrying a command that already
/// succeeded returns its stored result even when that creation filled the
/// author's quota.
///
/// `_post` (author `_author`) admits `_budder` through a forward edge;
/// `_request` is a Request owned by `_author`, who therefore already has two
/// recent creations (the Post and the Request).
const _author = 'Ubudrl0author';
const _budder = 'Ubudrl0budder';
const _users = [_author, _budder];

const _post = 'Bbudrl0post001';
const _request = 'Bbudrl0reqst01';

const _budderMsg = 'Rbudrl0budd001';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CHILD_CREATE_RATE_LIMIT_REPLAY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_child_rate_replay',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('child creation rate limit and command replay', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
    });

    setUp(() async {
      await _seed(writer);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    BeaconChildCreateCase buildCase({required int maxPerUser}) {
      final base = target.databaseEnv;
      final env = Env(
        environment: Environment.test,
        pgHost: base.pgHost,
        pgPort: base.pgPort,
        pgDatabase: base.pgDatabase,
        pgUsername: base.pgUsername,
        pgPassword: base.pgPassword,
        printEnv: false,
        isDebugModeOn: false,
        beaconCreateMaxPerUser: maxPerUser,
      );
      final logger = Logger('ChildCreateRateLimitReplayPgTest');
      final attention = TransactionalAttentionCase(
        MutatingUnitOfWork(database),
        AttentionDispatchRepository(database, logger),
      );
      final room = BeaconRoomRepository(database);
      final context = BeaconRoomNotificationContextRepository(
        room,
        database,
        HelpOfferRepository(database),
        CommitmentRepository(database),
      );
      final intents = AttentionIntentCase(
        context,
        UserRepository(
          env,
          database,
          _UnusedGenealogy(),
          InviteSeedPromptRepositoryMock(),
        ),
        BeaconAccessRepository(database),
        UserBlockRepository(env, database),
      );
      return BeaconChildCreateCase(
        BeaconRepository(database),
        BeaconHierarchyRepository(database),
        BeaconHierarchyCommandRepository(database),
        BeaconAccessRepository(database),
        context,
        attentionIntents: intents,
        attention: attention,
        postLock: PostLockRepository(database),
        postBud: PostBudRepository(database, _UnusedVisibility()),
        env: env,
        logger: logger,
      );
    }

    Future<BeaconChildCreateResult> bud(
      BeaconChildCreateCase children, {
      String commandId = 'cmd-bud-1',
      String title = 'Move the piano',
    }) => children.createChildUnderPost(
      actorUserId: _budder,
      postId: _post,
      sourceMessageId: _budderMsg,
      clientCommandId: commandId,
      title: title,
      description: 'Saturday, two people',
    );

    Future<BeaconChildCreateResult> createChild(
      BeaconChildCreateCase children, {
      String commandId = 'cmd-child-1',
    }) => children.createChild(
      actorUserId: _author,
      parentBeaconId: _request,
      clientCommandId: commandId,
      title: 'Move the piano',
      description: 'Saturday, two people',
      draft: false,
    );

    group('budding', () {
      // The budder already created two Requests recently, so with a cap of
      // three the bud takes the last available slot.
      const cap = 3;

      setUp(() async {
        await _seedRecentCreations(writer, _budder, count: cap - 1);
      });

      test(
        'retrying the bud that used the last creation slot replays it',
        () async {
          final children = buildCase(maxPerUser: cap);
          expect(await _beaconCountOf(writer, _budder), cap - 1);
          final first = await bud(children);
          expect(await _beaconCountOf(writer, _budder), cap);

          final retry = await bud(children);

          expect(retry.outcome, BeaconChildCommandOutcome.replayed);
          expect(retry.beaconId, first.beaconId);
          expect(retry.budResult, first.budResult);
          expect(await _beaconCountOf(writer, _budder), cap);
        },
      );

      test('a new bud command at the limit is still rate limited', () async {
        final children = buildCase(maxPerUser: cap);
        await bud(children);

        await expectLater(
          bud(children, commandId: 'cmd-bud-2', title: 'Another piano'),
          throwsA(isA<RateLimitedException>()),
        );
        expect(await _beaconCountOf(writer, _budder), cap);
      });

      test(
        'a replay with a different input still conflicts at the limit',
        () async {
          final children = buildCase(maxPerUser: cap);
          await bud(children);

          await expectLater(
            bud(children, title: 'A different title'),
            throwsA(isA<BeaconChildCommandConflictException>()),
          );
        },
      );
    });

    group('standalone child creation', () {
      test(
        'retrying the create that used the last creation slot replays it',
        () async {
          final children = buildCase(maxPerUser: 3);
          final first = await createChild(children);

          final retry = await createChild(children);

          expect(retry.outcome, BeaconChildCommandOutcome.replayed);
          expect(retry.beaconId, first.beaconId);
          expect(await _beaconCountOf(writer, _author), 3);
        },
      );

      test('a new create command at the limit is still rate limited', () async {
        final children = buildCase(maxPerUser: 3);
        await createChild(children);

        await expectLater(
          createChild(children, commandId: 'cmd-child-2'),
          throwsA(isA<RateLimitedException>()),
        );
        expect(await _beaconCountOf(writer, _author), 3);
      });
    });
  });
}

Future<int> _beaconCountOf(Connection writer, String userId) async {
  final rows = await writer.execute(
    Sql.named('SELECT count(*)::int FROM public.beacon WHERE user_id = @id'),
    parameters: {'id': userId},
  );
  return rows.single.single! as int;
}

/// Gives [userId] [count] recently created Requests, counting toward the
/// per-user creation cap.
Future<void> _seedRecentCreations(
  Connection writer,
  String userId, {
  required int count,
}) async {
  for (var i = 0; i < count; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES (@id, @userId, 'Earlier Request', '', 0, now())
'''),
      parameters: {'id': 'Bbudrl0prior0${i + 1}', 'userId': userId},
    );
  }
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.beacon_hierarchy_deliveries,
  public.beacon_hierarchy_events,
  public.attention_occurrence,
  public.beacon_child_commands,
  public.beacon_promotions,
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
      parameters: {'id': _users[i], 'key': pgTestPublicKey('budrl', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES
  ('$_post', '$_author', '', '', 0, 1, 1, false, now())
''');
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'A Request', '', 0, now())
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Fbudrl0e01', '$_post', '$_author', '$_budder')
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('$_budderMsg', '$_post', '$_budder', 'I could organise the move')
''');
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _UnusedVisibility extends Fake
    implements PersonVisibilityRepositoryPort {}

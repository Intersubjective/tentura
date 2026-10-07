@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/capability/capability_tag.dart';
import 'package:tentura_server/domain/entity/beacon_conversion_content.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Uconvertauth01';
const _member = 'Uconvertmemb01';
const _other = 'Uconvertother1';
const _users = [_author, _member, _other];

const _post = 'Bconvertpost01';
const _rootMessage = 'Rconvertroot01';
const _draftPost = 'Bconvertdraft1';
const _plainRequest = 'Bconvertreq001';

const _kindRequest = 0;
const _kindPost = 1;
const _statusOpen = 0;
const _statusDraft = 3;
const _policyClosed = 0;
const _policyOpen = 1;
const _roleAddressee = 6;

/// A Post's author turns it into a Request in one validated step: the Request
/// content, `kind`, forward policy and discoverability change together (one
/// `UPDATE`, because the Post shape CHECK forbids writing content first), an
/// empty helper selection removes the Post's addressees, and a system
/// message tells the room. Real repositories over a disposable Postgres.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_CONVERT_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_convert',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('BeaconCase conversion of a Post to a Request', () {
    late DisposablePgWriterSession session;
    late TenturaDb database;
    late Connection writer;
    late BeaconCase beacons;
    late Connection listener;
    late StreamSubscription<String> notificationSubscription;
    final notifications = <Map<String, dynamic>>[];

    final slugs = kCapabilitySlugOrder.take(2).toList();
    final start = DateTime.utc(2030, 5, 1, 9);
    final end = DateTime.utc(2030, 5, 3, 18);

    BeaconConversionContent validContent() => BeaconConversionContent(
      title: 'Help me move a piano',
      description: 'Third floor, no lift, Saturday.',
      needs: slugs.join(','),
      primaryNeedSlug: slugs.last,
      startAt: start,
      endAt: end,
    );

    Future<void> convertWithoutHelpers({
      required String authorId,
      required String beaconId,
      required BeaconConversionContent content,
      required bool isDiscoverable,
    }) async {
      // Keep the tests compilable before the helperIds argument is available.
      // Every conversion explicitly selects no helpers, including refusals.
      await (Function.apply(
            beacons.convertToRequest,
            const <Object?>[],
            <Symbol, Object?>{
              #authorId: authorId,
              #beaconId: beaconId,
              #content: content,
              #isDiscoverable: isDiscoverable,
              #helperIds: const <String>[],
            },
          )
          as Future<Object?>);
    }

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      beacons = _buildBeaconCase(database, target.databaseEnv);
      for (final statement in _updateLogDdl) {
        await writer.execute(statement);
      }
      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      notificationSubscription = listener.channels['entity_changes'].listen(
        (payload) =>
            notifications.add(jsonDecode(payload) as Map<String, dynamic>),
      );
    });

    setUp(() async {
      beacons.afterConvertUpdateForTest = null;
      await _seed(writer);
      await writer.execute(
        'TRUNCATE TABLE public.convert_test_beacon_update_log',
      );
      await _settle();
      notifications.clear();
    });

    tearDownAll(() async {
      await notificationSubscription.cancel();
      await listener.close();
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<ResultRow> beaconRow(String id) async => (await writer.execute('''
SELECT kind, forward_policy, is_discoverable, title, description, needs,
       primary_need_slug, start_at, end_at, updated_at, post_root_message_id
FROM public.beacon WHERE id = '$id'
''')).single;

    Future<List<ResultRow>> systemMessages(String id, int kind) =>
        writer.execute('''
SELECT system_payload::text, author_id, body
FROM public.beacon_room_message
WHERE beacon_id = '$id' AND system_message_kind = $kind
''');

    Future<ResultRow?> participant(String beaconId, String userId) async =>
        (await writer.execute('''
SELECT role, room_access FROM public.beacon_participant
WHERE beacon_id = '$beaconId' AND user_id = '$userId'
''')).singleOrNull;

    Future<Set<String>> admittedHelpers(String beaconId) async =>
        (await writer.execute('''
SELECT user_id FROM public.beacon_admitted_helper
WHERE beacon_id = '$beaconId'
''')).map((r) => r.single! as String).toSet();

    Future<int> contentUpdateCount(String id) async =>
        (await writer.execute('''
SELECT count(*) FROM public.convert_test_beacon_update_log
WHERE beacon_id = '$id'
''')).single.single!
            as int;

    List<Map<String, dynamic>> beaconUpdateNotices(String id) => notifications
        .where(
          (n) =>
              n['entity'] == 'beacon' &&
              n['event'] == 'update' &&
              n['id'] == id,
        )
        .toList();

    test(
      'the seeded Post starts as an empty Post with two addressees',
      () async {
        final row = await beaconRow(_post);
        expect(row[0], _kindPost);
        expect(row[1], _policyClosed);
        expect((await participant(_post, _member))![0], _roleAddressee);
        expect((await participant(_post, _other))![0], _roleAddressee);
      },
    );

    group('with valid content', () {
      test('turns the Post into an open-forwarding Request', () async {
        await convertWithoutHelpers(
          authorId: _author,
          beaconId: _post,
          content: validContent(),
          isDiscoverable: false,
        );

        final row = await beaconRow(_post);
        expect(row[0], _kindRequest, reason: 'kind');
        expect(row[1], _policyOpen, reason: 'forward_policy');
      });

      test('writes the Request content', () async {
        await convertWithoutHelpers(
          authorId: _author,
          beaconId: _post,
          content: validContent(),
          isDiscoverable: false,
        );

        final row = await beaconRow(_post);
        expect(row[3], 'Help me move a piano');
        expect(row[4], 'Third floor, no lift, Saturday.');
        expect((row[5]! as String).split(',').toSet(), slugs.toSet());
        expect(row[6], slugs.last);
        expect((row[7]! as DateTime).toUtc(), start);
        expect((row[8]! as DateTime).toUtc(), end);
      });

      test(
        'writes kind, forward policy and every content column in a single '
        'UPDATE of the beacon row',
        () async {
          await convertWithoutHelpers(
            authorId: _author,
            beaconId: _post,
            content: validContent(),
            isDiscoverable: true,
          );

          expect(
            await contentUpdateCount(_post),
            1,
            reason:
                'the Post shape CHECK forbids writing content before the '
                'kind flips, so the conversion must be one statement',
          );
        },
      );

      test('emits a realtime beacon update to the author', () async {
        await convertWithoutHelpers(
          authorId: _author,
          beaconId: _post,
          content: validContent(),
          isDiscoverable: false,
        );
        await _waitUntil(() => beaconUpdateNotices(_post).isNotEmpty);

        expect(
          beaconUpdateNotices(_post).first['user_ids'],
          contains(_author),
        );
      });

      test(
        'conversion beacon hints include carried-over helpers and all '
        'Request publication recipients',
        () async {
          Future<void> barrier(String id) async {
            await writer.execute(
              Sql.named("SELECT pg_notify('entity_changes', @payload)"),
              parameters: {
                'payload': jsonEncode({'entity': 'barrier', 'id': id}),
              },
            );
            await _waitUntil(
              () => notifications.any(
                (n) => n['entity'] == 'barrier' && n['id'] == id,
              ),
            );
          }

          await barrier('conversion-before');
          notifications.clear();
          expect(await participant(_post, _author), isNull);
          expect((await participant(_post, _other))![0], _roleAddressee);
          Future<List<ResultRow>> activeForwardsToOther() => writer.execute(
            Sql.named('''
SELECT id FROM public.beacon_forward_edge
WHERE beacon_id = @beacon AND recipient_id = @recipient
  AND cancelled_at IS NULL
'''),
            parameters: {'beacon': _post, 'recipient': _other},
          );
          expect(await activeForwardsToOther(), hasLength(1));
          await beacons.convertToRequest(
            authorId: _author,
            beaconId: _post,
            content: validContent(),
            isDiscoverable: true,
            helperIds: const [_member],
          );
          await barrier('conversion-after');

          expect((await beaconRow(_post))[0], _kindRequest);
          expect(await admittedHelpers(_post), unorderedEquals([_member]));
          expect(await participant(_post, _other), isNull);
          expect(await activeForwardsToOther(), hasLength(1));
          final notices = beaconUpdateNotices(_post);
          expect(notices, isNotEmpty);
          final recipients = notices
              .expand((n) => (n['user_ids']! as List).cast<String>())
              .toSet();
          final publicationRecipients = (await writer.execute(
            Sql.named(
              'SELECT unnest(public.realtime_beacon_recipients(@beacon))',
            ),
            parameters: {'beacon': _post},
          )).map((row) => row.single! as String).toSet();
          expect(publicationRecipients, contains(_other));
          expect(recipients, containsAll([_author, _member, _other]));
          expect(
            recipients,
            contains(_other),
            reason:
                'an active forward recipient is notified without being a helper',
          );
          expect(recipients, containsAll(publicationRecipients));
          for (final notice in notices) {
            expect(notice['actor_user_id'], _author);
            expect(notice.containsKey('title'), isFalse);
            expect(notice.containsKey('description'), isFalse);
          }
        },
      );

      test('keeps the root message of the Post', () async {
        expect((await beaconRow(_post))[10], _rootMessage);

        await convertWithoutHelpers(
          authorId: _author,
          beaconId: _post,
          content: validContent(),
          isDiscoverable: false,
        );

        expect((await beaconRow(_post))[10], _rootMessage);
        final rows = await writer.execute('''
SELECT count(*) FROM public.beacon_room_message WHERE id = '$_rootMessage'
''');
        expect(
          rows.single.single,
          1,
          reason: 'the root message is not deleted',
        );
      });

      test('stores the requested discoverability', () async {
        await convertWithoutHelpers(
          authorId: _author,
          beaconId: _post,
          content: validContent(),
          isDiscoverable: true,
        );

        expect((await beaconRow(_post))[2], isTrue);
      });

      test('bumps updated_at', () async {
        final before = (await beaconRow(_post))[9]! as DateTime;

        await convertWithoutHelpers(
          authorId: _author,
          beaconId: _post,
          content: validContent(),
          isDiscoverable: false,
        );

        final after = (await beaconRow(_post))[9]! as DateTime;
        expect(after.isAfter(before), isTrue);
      });

      test(
        'inserts exactly one system message announcing the conversion',
        () async {
          await convertWithoutHelpers(
            authorId: _author,
            beaconId: _post,
            content: validContent(),
            isDiscoverable: false,
          );

          final rows = await systemMessages(
            _post,
            BeaconRoomSystemMessageKind.convertedToRequest,
          );
          expect(rows, hasLength(1));
          expect(
            rows.single[0],
            anyOf(
              '{"event": "convertedToRequest"}',
              '{"event":"convertedToRequest"}',
            ),
          );
          expect(rows.single[1], isNull, reason: 'system rows have no author');
        },
      );

      test('an empty helper selection removes every Post addressee', () async {
        await convertWithoutHelpers(
          authorId: _author,
          beaconId: _post,
          content: validContent(),
          isDiscoverable: false,
        );

        for (final user in [_member, _other]) {
          expect(
            await participant(_post, user),
            isNull,
            reason: '$user is not selected as a Request helper',
          );
        }
      });

      test('an empty helper selection does not admit helpers', () async {
        await convertWithoutHelpers(
          authorId: _author,
          beaconId: _post,
          content: validContent(),
          isDiscoverable: false,
        );

        expect(await admittedHelpers(_post), isEmpty);
      });

      test('leaves the other Post and the plain Request untouched', () async {
        final draftBefore = await beaconRow(_draftPost);
        final requestBefore = await beaconRow(_plainRequest);

        await convertWithoutHelpers(
          authorId: _author,
          beaconId: _post,
          content: validContent(),
          isDiscoverable: false,
        );

        expect(await beaconRow(_draftPost), draftBefore);
        expect(await beaconRow(_plainRequest), requestBefore);
      });
    });

    group('with content the Request rules reject', () {
      Future<void> expectRejectedAndUnchanged(
        BeaconConversionContent content,
      ) async {
        final before = await beaconRow(_post);

        await expectLater(
          convertWithoutHelpers(
            authorId: _author,
            beaconId: _post,
            content: content,
            isDiscoverable: false,
          ),
          throwsA(isA<BeaconCreateException>()),
        );

        expect(await beaconRow(_post), before, reason: 'the Post is unchanged');
        expect(
          await systemMessages(
            _post,
            BeaconRoomSystemMessageKind.convertedToRequest,
          ),
          isEmpty,
        );
      }

      test('an empty title is a BeaconCreateException', () async {
        await expectRejectedAndUnchanged(
          BeaconConversionContent(
            title: '   ',
            description: 'Third floor, no lift, Saturday.',
          ),
        );
      });

      test('an empty description is a BeaconCreateException', () async {
        await expectRejectedAndUnchanged(
          BeaconConversionContent(title: 'Help me move a piano'),
        );
      });
    });

    group('refusals', () {
      test('a user who is not the author cannot convert the Post', () async {
        final before = await beaconRow(_post);

        await expectLater(
          convertWithoutHelpers(
            authorId: _member,
            beaconId: _post,
            content: validContent(),
            isDiscoverable: false,
          ),
          throwsA(isA<UnauthorizedException>()),
        );

        expect(await beaconRow(_post), before);
        expect(
          await systemMessages(
            _post,
            BeaconRoomSystemMessageKind.convertedToRequest,
          ),
          isEmpty,
        );
      });

      test('a second conversion is rejected and changes nothing', () async {
        await convertWithoutHelpers(
          authorId: _author,
          beaconId: _post,
          content: validContent(),
          isDiscoverable: false,
        );
        final afterFirst = await beaconRow(_post);

        await expectLater(
          convertWithoutHelpers(
            authorId: _author,
            beaconId: _post,
            content: BeaconConversionContent(
              title: 'A different title',
              description: 'A different description',
            ),
            isDiscoverable: true,
          ),
          throwsA(isA<ExceptionBase>()),
        );

        expect(await beaconRow(_post), afterFirst);
        expect(
          await systemMessages(
            _post,
            BeaconRoomSystemMessageKind.convertedToRequest,
          ),
          hasLength(1),
        );
      });

      test('a plain Request cannot be converted', () async {
        final before = await beaconRow(_plainRequest);

        await expectLater(
          convertWithoutHelpers(
            authorId: _author,
            beaconId: _plainRequest,
            content: validContent(),
            isDiscoverable: false,
          ),
          throwsA(isA<ExceptionBase>()),
        );

        expect(await beaconRow(_plainRequest), before);
        expect(
          await systemMessages(
            _plainRequest,
            BeaconRoomSystemMessageKind.convertedToRequest,
          ),
          isEmpty,
        );
      });

      test('a draft Post cannot be converted', () async {
        final before = await beaconRow(_draftPost);

        await expectLater(
          convertWithoutHelpers(
            authorId: _author,
            beaconId: _draftPost,
            content: validContent(),
            isDiscoverable: false,
          ),
          throwsA(isA<ExceptionBase>()),
        );

        expect(await beaconRow(_draftPost), before);
        expect((await beaconRow(_draftPost))[0], _kindPost);
      });
    });

    test(
      'a failure after the UPDATE rolls the whole conversion back',
      () async {
        final before = await beaconRow(_post);
        beacons.afterConvertUpdateForTest = () async {
          throw StateError('injected failure after the UPDATE');
        };

        await expectLater(
          convertWithoutHelpers(
            authorId: _author,
            beaconId: _post,
            content: validContent(),
            isDiscoverable: true,
          ),
          throwsA(isA<StateError>()),
        );

        expect(await beaconRow(_post), before, reason: 'still the same Post');
        expect(
          await systemMessages(
            _post,
            BeaconRoomSystemMessageKind.convertedToRequest,
          ),
          isEmpty,
          reason: 'no system message survives the rollback',
        );
        expect(
          (await participant(_post, _member))![1],
          RoomAccessBits.admitted,
        );
        await _settle();
        expect(
          beaconUpdateNotices(_post),
          isEmpty,
          reason: 'a rolled-back conversion announces nothing',
        );
        expect(await contentUpdateCount(_post), 0);
      },
    );
  });
}

/// Test-only trigger that records one row per UPDATE of the beacon that
/// changes anything a conversion writes, so a conversion split into several
/// statements is visible.
const _updateLogDdl = [
  '''
CREATE TABLE IF NOT EXISTS public.convert_test_beacon_update_log (
  id bigserial PRIMARY KEY,
  beacon_id text NOT NULL
)
''',
  r'''
CREATE OR REPLACE FUNCTION public.convert_test_log_beacon_update()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.convert_test_beacon_update_log (beacon_id)
  VALUES (NEW.id);
  RETURN NULL;
END
$$
''',
  '''
CREATE TRIGGER convert_test_beacon_update_trg
AFTER UPDATE ON public.beacon
FOR EACH ROW
WHEN (
  OLD.kind IS DISTINCT FROM NEW.kind
  OR OLD.forward_policy IS DISTINCT FROM NEW.forward_policy
  OR OLD.is_discoverable IS DISTINCT FROM NEW.is_discoverable
  OR OLD.title IS DISTINCT FROM NEW.title
  OR OLD.description IS DISTINCT FROM NEW.description
  OR OLD.needs IS DISTINCT FROM NEW.needs
  OR OLD.primary_need_slug IS DISTINCT FROM NEW.primary_need_slug
  OR OLD.start_at IS DISTINCT FROM NEW.start_at
  OR OLD.end_at IS DISTINCT FROM NEW.end_at
)
EXECUTE FUNCTION public.convert_test_log_beacon_update()
''',
];

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.timestamp().add(timeout);
  while (!condition()) {
    if (DateTime.timestamp().isAfter(deadline)) {
      fail('Condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.inbox_item,
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
      parameters: {'id': _users[i], 'key': pgTestPublicKey('convert', i + 1)},
    );
  }
  // An open, closed-forwarding Post forwarded to two addressees; the
  // forward-edge trigger admits both (`role 6`, `room_access 3`).
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, updated_at)
VALUES ('$_post', '$_author', '', '', $_statusOpen, $_kindPost, $_policyClosed,
        false, now() - interval '1 day', now() - interval '1 day')
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES
  ('Fconvertauthmem1', '$_post', '$_author', '$_member'),
  ('Fconvertauthoth1', '$_post', '$_author', '$_other')
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('$_rootMessage', '$_post', '$_author', 'Anyone around on Saturday?')
''');
  await writer.execute('''
UPDATE public.beacon SET post_root_message_id = '$_rootMessage'
WHERE id = '$_post'
''');
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable)
VALUES ('$_draftPost', '$_author', '', '', $_statusDraft, $_kindPost,
        $_policyClosed, false)
''');
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at)
VALUES ('$_plainRequest', '$_author', 'Plain', 'A plain request', $_statusOpen,
        $_kindRequest, now())
''');
}

BeaconCase _buildBeaconCase(TenturaDb db, Env env) {
  final logger = Logger('PostConvertPgTest');
  final uow = MutatingUnitOfWork(db);
  final attention = TransactionalAttentionCase(
    uow,
    AttentionDispatchRepository(db, logger),
  );
  final help = HelpOfferRepository(db);
  final commitments = CommitmentRepository(db);
  final access = BeaconAccessRepository(db);
  final blocks = UserBlockRepository(env, db);
  final intents = AttentionIntentCase(
    BeaconRoomNotificationContextRepository(
      BeaconRoomRepository(db),
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
  return BeaconCase(
    BeaconRepository(db),
    _UnusedImages(),
    _UnusedImageGc(),
    _Tasks(),
    CommitmentQueryCase(commitments, help, env: env, logger: logger),
    access,
    BeaconHierarchyRepository(db),
    FakeBeaconChildCreatePort(),
    BeaconLifecycleEffectsCase(
      BeaconHierarchyOutboxRepository(db),
      env: env,
      logger: logger,
    ),
    postLock: PostLockRepository(db),
    attentionIntents: intents,
    attention: attention,
    env: env,
    logger: logger,
  );
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedImageGc extends Fake implements ImageObjectGcPort {}

final class _Tasks extends Fake implements TaskRepositoryPort {
  @override
  Future<String> schedule(TaskEntity task) async => 'task-id';
}

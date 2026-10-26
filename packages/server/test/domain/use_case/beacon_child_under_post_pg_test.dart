@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_command_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
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
import 'package:tentura_server/domain/entity/post_parent_stage.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_command_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_child_create_case.dart';
import 'package:tentura_server/domain/use_case/beacon_hierarchy_delivery_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// Budding C1: the Post-parent branch of the child pipeline
/// (`createChildUnderPost`, Arch §3.1, §4.2).
///
/// `_post` (author `_author`) admits `_budder` and `_member` through forward
/// edges; `_outsider` is not a member. `_budderMsg` is the budder's own
/// message, `_memberMsg` someone else's, `_rootMsg` the author's.
const _author = 'Ubudc1author1';
const _budder = 'Ubudc1budder1';
const _member = 'Ubudc1member1';
const _outsider = 'Ubudc1outsid1';
const _users = [_author, _budder, _member, _outsider];

const _post = 'Bbudc1post001';
const _draftPost = 'Bbudc1draft01';
const _request = 'Bbudc1reqst01';

const _rootMsg = 'Rbudc1root001';
const _budderMsg = 'Rbudc1budd001';
const _memberMsg = 'Rbudc1memb001';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_CHILD_UNDER_POST_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_child_under_post',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('createChildUnderPost', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late BeaconChildCreateCase children;
    late BeaconLifecycleEffectsCase lifecycleEffects;
    late BeaconHierarchyDeliveryCase delivery;
    late MutatingUnitOfWork uow;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      final env = target.databaseEnv;
      final logger = Logger('BeaconChildUnderPostPgTest');
      uow = MutatingUnitOfWork(database);
      final attention = TransactionalAttentionCase(
        uow,
        AttentionDispatchRepository(database, logger),
      );
      final room = BeaconRoomRepository(database);
      final intents = AttentionIntentCase(
        BeaconRoomNotificationContextRepository(
          room,
          database,
          HelpOfferRepository(database),
          CommitmentRepository(database),
        ),
        UserRepository(
          env,
          database,
          _UnusedGenealogy(),
          InviteSeedPromptRepositoryMock(),
        ),
        BeaconAccessRepository(database),
        UserBlockRepository(env, database),
      );
      final outbox = BeaconHierarchyOutboxRepository(database);
      children = BeaconChildCreateCase(
        BeaconRepository(database),
        BeaconHierarchyRepository(database),
        BeaconHierarchyCommandRepository(database),
        BeaconAccessRepository(database),
        BeaconRoomNotificationContextRepository(
          room,
          database,
          HelpOfferRepository(database),
          CommitmentRepository(database),
        ),
        attentionIntents: intents,
        attention: attention,
        postLock: PostLockRepository(database),
        postBud: PostBudRepository(database, _UnusedVisibility()),
        env: env,
        logger: logger,
      );
      lifecycleEffects = BeaconLifecycleEffectsCase(
        outbox,
        env: env,
        logger: logger,
      );
      delivery = BeaconHierarchyDeliveryCase(
        outbox,
        attention,
        intents,
        env: env,
        logger: logger,
      );
    });

    setUp(() async {
      await _seed(writer);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<BeaconChildCreateResult> bud({
      String actor = _budder,
      String postId = _post,
      String source = _budderMsg,
      String commandId = 'cmd-bud-1',
      String title = 'Move the piano',
      String? description = 'Saturday, two people',
      bool isDiscoverable = false,
      Map<String, Object?> budInput = const {},
      PostParentStage? stage,
    }) => children.createChildUnderPost(
      actorUserId: actor,
      postId: postId,
      sourceMessageId: source,
      clientCommandId: commandId,
      title: title,
      description: description,
      isDiscoverable: isDiscoverable,
      budInput: budInput,
      stage: stage,
    );

    test(
      'creates the child, runs the stage and stores the bud result',
      () async {
        final calls = <String>[];
        PostParentStageContext? seen;
        final result = await bud(
          budInput: const {'closePost': false},
          stage: (context) async {
            seen = context;
            calls.add('stage');
            final notices = await _childCreatedNotices(writer);
            expect(notices, isEmpty, reason: 'notice follows the stage');
            return PostParentStageResult(
              invitedCount: 2,
              invitees: const [
                {'userId': _member, 'outcome': 'invited'},
                {'userId': _author, 'outcome': 'invited'},
              ],
              afterNotice: () async => calls.add('afterNotice'),
            );
          },
        );

        expect(calls, ['stage', 'afterNotice']);
        expect(seen!.actorUserId, _budder);
        expect(seen!.postId, _post);
        expect(seen!.sourceMessageId, _budderMsg);
        expect(seen!.child.status, BeaconStatus.open);
        expect(seen!.child.parentBeaconId, _post);

        expect(result.outcome, BeaconChildCommandOutcome.created);
        final childId = result.beaconId!;
        final expectedResult = {
          'outcome': 'created',
          'childBeaconId': childId,
          'invitees': [
            {'userId': _member, 'outcome': 'invited'},
            {'userId': _author, 'outcome': 'invited'},
          ],
        };
        expect(result.budResult, expectedResult);

        final command = await _command(writer, 'cmd-bud-1');
        expect(command.budResult, expectedResult);
        expect(
          command.hash,
          startsWith(BeaconChildCreateCase.budInputHashPrefix),
        );
        expect(command.resultBeaconId, childId);
        expect(command.anchorInheritedAt, isNull);

        final promotion = await writer.execute(
          Sql.named(
            'SELECT parent_beacon_id, source_message_id, published_at '
            'FROM public.beacon_promotions WHERE child_beacon_id = @c',
          ),
          parameters: {'c': childId},
        );
        expect(promotion.single[0], _post);
        // Post buds leave source unbound so budding stays unlimited (D3).
        expect(promotion.single[1], isNull);
        expect(promotion.single[2], isNotNull);

        final notices = await _childCreatedNotices(writer);
        expect(notices, hasLength(1));
        expect(notices.single, {
          'version': 1,
          'kind': 'childCreated',
          'childBeaconId': childId,
          'sourceMessageId': _budderMsg,
          'title': 'Move the piano',
          'invitedCount': 2,
        });
        expect(await _occurrences(writer, 'child_created_notice:%'), 0);
      },
    );

    test(
      'keeps the client title and description, not the source body',
      () async {
        final result = await bud(description: 'My own words');
        final row = await _child(writer, result.beaconId!);
        expect(row.title, 'Move the piano');
        expect(row.description, 'My own words');
      },
    );

    test(
      'persists isDiscoverable: false by default, true on request',
      () async {
        final hidden = await bud();
        expect(
          (await _child(writer, hidden.beaconId!)).isDiscoverable,
          isFalse,
        );

        final visible = await bud(
          actor: _member,
          source: _memberMsg,
          commandId: 'cmd-bud-2',
          isDiscoverable: true,
        );
        expect(
          (await _child(writer, visible.beaconId!)).isDiscoverable,
          isTrue,
        );
      },
    );

    test('without a stage the notice counts zero invites', () async {
      final result = await bud();
      expect(result.budResult, {
        'outcome': 'created',
        'childBeaconId': result.beaconId,
        'invitees': <Object?>[],
      });
      expect((await _childCreatedNotices(writer)).single['invitedCount'], 0);
    });

    test('the Post author may bud from the root message', () async {
      final result = await bud(actor: _author, source: _rootMsg);
      expect(result.outcome, BeaconChildCommandOutcome.created);
    });

    group('replay', () {
      test(
        'returns the stored result without new rows or a second stage',
        () async {
          var stageRuns = 0;
          Future<PostParentStageResult> stage(PostParentStageContext _) async {
            stageRuns++;
            return const PostParentStageResult(
              invitedCount: 1,
              invitees: [
                {'userId': _member, 'outcome': 'invited'},
              ],
            );
          }

          final first = await bud(stage: stage);
          final second = await bud(stage: stage);

          expect(stageRuns, 1);
          expect(second.outcome, BeaconChildCommandOutcome.replayed);
          expect(second.beaconId, first.beaconId);
          expect(second.budResult, first.budResult);
          expect(await _childCount(writer), 1);
          expect(await _childCreatedNotices(writer), hasLength(1));
        },
      );

      test('works after the Post is closed', () async {
        final first = await bud();
        await writer.execute(
          'UPDATE public.beacon SET status = '
          '${BeaconStatus.closed.smallintValue} '
          "WHERE id = '$_post'",
        );
        final second = await bud();
        expect(second.outcome, BeaconChildCommandOutcome.replayed);
        expect(second.budResult, first.budResult);
      });

      test('works after the budder lost membership', () async {
        final first = await bud();
        await writer.execute(
          'UPDATE public.beacon_participant SET room_access = 5 '
          "WHERE beacon_id = '$_post' AND user_id = '$_budder'",
        );
        final second = await bud();
        expect(second.budResult, first.budResult);
      });

      test('a different input under the same command id conflicts', () async {
        await bud();
        await expectLater(
          bud(title: 'Something else'),
          throwsA(isA<BeaconChildCommandConflictException>()),
        );
        await expectLater(
          bud(isDiscoverable: true),
          throwsA(isA<BeaconChildCommandConflictException>()),
        );
        await expectLater(
          bud(budInput: const {'closePost': true}),
          throwsA(isA<BeaconChildCommandConflictException>()),
        );
      });

      test('a command id used by createChild conflicts', () async {
        await children.createChild(
          actorUserId: _author,
          parentBeaconId: _request,
          clientCommandId: 'cmd-shared',
          title: 'Move the piano',
          description: 'Saturday, two people',
          draft: false,
        );
        await expectLater(
          bud(actor: _author, source: _rootMsg, commandId: 'cmd-shared'),
          throwsA(isA<BeaconChildCommandConflictException>()),
        );
      });
    });

    group('unlimited budding', () {
      test('a second bud on the same source creates another child', () async {
        final first = await bud();
        final second = await bud(commandId: 'cmd-bud-again');

        expect(second.outcome, BeaconChildCommandOutcome.created);
        expect(second.beaconId, isNot(first.beaconId));
        expect(await _childCount(writer), 2);

        final replay = await bud(commandId: 'cmd-bud-again');
        expect(replay.outcome, BeaconChildCommandOutcome.replayed);
        expect(replay.beaconId, second.beaconId);
        expect(await _childCount(writer), 2);
      });

      test('blank source buds without a message', () async {
        final result = await bud(source: '  ', commandId: 'cmd-bud-blank');
        expect(result.outcome, BeaconChildCommandOutcome.created);
        expect(await _childCount(writer), 1);
        final notices = await _childCreatedNotices(writer);
        expect(notices.single.containsKey('sourceMessageId'), isFalse);
      });
    });

    group('guards', () {
      test('a non-member is forbidden', () async {
        await expectLater(
          bud(actor: _outsider),
          throwsA(isA<BeaconChildCreateForbiddenException>()),
        );
      });

      test('a member who left is forbidden', () async {
        await writer.execute(
          'UPDATE public.beacon_participant SET room_access = 5 '
          "WHERE beacon_id = '$_post' AND user_id = '$_budder'",
        );
        await expectLater(
          bud(),
          throwsA(isA<BeaconChildCreateForbiddenException>()),
        );
      });

      test('a draft Post is not open', () async {
        await expectLater(
          bud(actor: _author, postId: _draftPost, source: 'Rbudc1draft01'),
          throwsA(isA<PostNotOpenException>()),
        );
      });

      test('a draft Post is not open', () async {
        await writer.execute(
          'UPDATE public.beacon SET status = '
          '${BeaconStatus.draft.smallintValue} '
          "WHERE id = '$_post'",
        );
        await expectLater(bud(), throwsA(isA<PostNotOpenException>()));
      });

      test("someone else's message is rejected", () async {
        await expectLater(
          bud(source: _memberMsg),
          throwsA(isA<BudSourceNotOwnMessageException>()),
        );
        await expectLater(
          bud(source: _rootMsg),
          throwsA(isA<BudSourceNotOwnMessageException>()),
        );
      });

      test('a missing source message id is rejected when provided', () async {
        await expectLater(
          bud(source: 'Rbudc1missing'),
          throwsA(isA<BeaconPromotionSourceInvalidException>()),
        );
      });

      test('a Request parent is refused', () async {
        await expectLater(
          bud(actor: _author, postId: _request, source: 'Rbudc1reqm001'),
          throwsA(isA<BeaconChildCreateForbiddenException>()),
        );
      });

      test('a failed guard leaves no rows', () async {
        await expectLater(
          bud(source: _memberMsg),
          throwsA(isA<BudSourceNotOwnMessageException>()),
        );
        expect(await _childCount(writer), 0);
        final commands = await writer.execute(
          'SELECT count(*)::int FROM public.beacon_child_commands',
        );
        expect(commands.single.single, 0);
      });
    });

    test('createChild with a Post parent requires budding', () async {
      await expectLater(
        children.createChild(
          actorUserId: _author,
          parentBeaconId: _post,
          sourceMessageId: _rootMsg,
          clientCommandId: 'cmd-plain',
          title: 'Plain child',
          description: 'Not through a bud',
          draft: false,
        ),
        throwsA(isA<PostChildRequiresBudException>()),
      );
      await expectLater(
        children.createChild(
          actorUserId: _author,
          parentBeaconId: _draftPost,
          clientCommandId: 'cmd-plain-draft',
          title: 'Plain child',
          description: 'Not through a bud',
          draft: true,
        ),
        throwsA(isA<PostChildRequiresBudException>()),
      );
    });

    test(
      'a child lifecycle notice reaches the Post room with no receipts',
      () async {
        final result = await bud();
        final childId = result.beaconId!;

        await uow.run(
          actorUserId: _budder,
          action: () => lifecycleEffects.recordEligibleSourceTransition(
            sourceBeaconId: childId,
            fromStatus: BeaconStatus.open,
            toStatus: BeaconStatus.cancelled,
            occurredAt: DateTime.timestamp(),
            actorUserId: _budder,
            reason: BeaconStatusTransitionReason.cancelled,
          ),
        );
        await delivery.runDue(
          workerId: 'budc1-worker',
          now: DateTime.timestamp().add(const Duration(minutes: 1)),
        );

        final notices = await writer.execute(
          Sql.named(
            'SELECT count(*)::int FROM public.beacon_room_message '
            'WHERE beacon_id = @p AND hierarchy_notice_identity LIKE @k',
          ),
          parameters: {'p': _post, 'k': 'hierarchy:%'},
        );
        expect(notices.single.single, 1);
        final deliveries = await writer.execute(
          Sql.named(
            'SELECT state FROM public.beacon_hierarchy_deliveries '
            'WHERE target_beacon_id = @p',
          ),
          parameters: {'p': _post},
        );
        expect(deliveries.single.single, 'delivered');
        expect(await _occurrences(writer, 'hierarchy:%'), 0);
      },
    );
  });
}

Future<List<Map<String, Object?>>> _childCreatedNotices(
  Connection writer,
) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT system_payload::text FROM public.beacon_room_message '
      "WHERE beacon_id = @p AND hierarchy_notice_identity LIKE 'child_created:%'",
    ),
    parameters: {'p': _post},
  );
  return [
    for (final r in rows)
      (jsonDecode(r.single! as String) as Map).cast<String, Object?>(),
  ];
}

Future<int> _occurrences(Connection writer, String keyPattern) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT count(*)::int FROM public.attention_occurrence_recipient r '
      'JOIN public.attention_occurrence o ON o.id = r.occurrence_id '
      'WHERE o.source_event_key LIKE @k',
    ),
    parameters: {'k': keyPattern},
  );
  return rows.single.single! as int;
}

Future<int> _childCount(Connection writer) async {
  final rows = await writer.execute(
    "SELECT count(*)::int FROM public.beacon WHERE parent_beacon_id = '$_post'",
  );
  return rows.single.single! as int;
}

typedef _ChildRow = ({String title, String description, bool isDiscoverable});

Future<_ChildRow> _child(Connection writer, String id) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT title, description, is_discoverable FROM public.beacon '
      'WHERE id = @id',
    ),
    parameters: {'id': id},
  );
  final r = rows.single;
  return (
    title: r[0]! as String,
    description: r[1]! as String,
    isDiscoverable: r[2]! as bool,
  );
}

typedef _CommandRow = ({
  String hash,
  String? resultBeaconId,
  Map<String, Object?>? budResult,
  Object? anchorInheritedAt,
});

Future<_CommandRow> _command(Connection writer, String commandId) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT normalized_input_hash, result_beacon_id, bud_result::text, '
      'anchor_inherited_at FROM public.beacon_child_commands '
      'WHERE client_command_id = @c',
    ),
    parameters: {'c': commandId},
  );
  final r = rows.single;
  final raw = r[2] as String?;
  return (
    hash: r[0]! as String,
    resultBeaconId: r[1] as String?,
    budResult: raw == null
        ? null
        : (jsonDecode(raw) as Map).cast<String, Object?>(),
    anchorInheritedAt: r[3],
  );
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
      parameters: {'id': _users[i], 'key': pgTestPublicKey('budc1', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES
  ('$_post', '$_author', '', '', 0, 1, 1, false, now()),
  ('$_draftPost', '$_author', '', '', ${BeaconStatus.draft.smallintValue}, 1,
   1, false, NULL)
''');
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'A Request', '', 0, now())
''');
  // Forward edges admit the recipients (m0210).
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Fbudc1e01', '$_post', '$_author', '$_budder'),
       ('Fbudc1e02', '$_post', '$_author', '$_member'),
       ('Fbudc1e03', '$_request', '$_author', '$_budder')
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES
  ('$_rootMsg', '$_post', '$_author', 'Who has a van?'),
  ('$_budderMsg', '$_post', '$_budder', 'I could organise the move'),
  ('$_memberMsg', '$_post', '$_member', 'I have a van'),
  ('Rbudc1draft01', '$_draftPost', '$_author', 'Draft body'),
  ('Rbudc1reqm001', '$_request', '$_author', 'Request message')
''');
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _UnusedVisibility extends Fake
    implements PersonVisibilityRepositoryPort {}

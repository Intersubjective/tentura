@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_command_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/bud_anchor_sweep_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/post_bud_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/post_bud.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/use_case/anchor_inherit_operation.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_child_create_case.dart';
import 'package:tentura_server/domain/use_case/bud_anchor_sweep_case.dart';
import 'package:tentura_server/domain/use_case/post_bud_case.dart';
import 'package:tentura_server/domain/use_case/post_close_operation.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// Budding a Request from a Post that already ended (closed by its author, or
/// expired but not yet swept): members may still bud, and budding never ends
/// a Post a second time.
///
/// `_post` (author `_author`) admits `_budder` and `_invitee` through forward
/// edges; `_outsider` has no edge.
const _author = 'Ubarc1author01';
const _budder = 'Ubarc1budder01';
const _invitee = 'Ubarc1invitee1';
const _outsider = 'Ubarc1outsider';
const _users = [_author, _budder, _invitee, _outsider];

const _post = 'Bbarc1post0001';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_BUD_FROM_ARCHIVE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_bud_from_archive',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Budding a Request from an archived Post', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late MutatingUnitOfWork uow;
    late PostCloseOperation postClose;
    late PostBudCase buds;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      uow = MutatingUnitOfWork(database);
      final env = target.databaseEnv;
      final logger = Logger('PostBudFromArchivePgTest');
      final attention = TransactionalAttentionCase(
        uow,
        AttentionDispatchRepository(database, logger),
      );
      final room = BeaconRoomRepository(database);
      final notificationContext = BeaconRoomNotificationContextRepository(
        room,
        database,
        HelpOfferRepository(database),
        CommitmentRepository(database),
      );
      final intents = AttentionIntentCase(
        notificationContext,
        UserRepository(
          env,
          database,
          _UnusedGenealogy(),
          InviteSeedPromptRepositoryMock(),
        ),
        BeaconAccessRepository(database),
        UserBlockRepository(env, database),
      );
      final postBud = PostBudRepository(
        database,
        _Visibility({_invitee, _budder}),
      );
      final beacons = BeaconRepository(database);
      final anchorSweepPort = BudAnchorSweepRepository(database);
      postClose = PostCloseOperation(beacons);
      buds = PostBudCase(
        BeaconChildCreateCase(
          beacons,
          BeaconHierarchyRepository(database),
          BeaconHierarchyCommandRepository(database),
          BeaconAccessRepository(database),
          notificationContext,
          attentionIntents: intents,
          attention: attention,
          postLock: PostLockRepository(database),
          postBud: postBud,
          env: env,
          logger: logger,
        ),
        postBud,
        ForwardEdgeRepository(database),
        InboxRepository(database),
        intents,
        postClose,
        BudAnchorSweepCase(
          anchorSweepPort,
          AnchorInheritOperation(
            ConstellationAnchorRepository(database),
            anchorSweepPort,
          ),
          env: env,
          logger: logger,
        ),
      );
    });

    setUp(() async => _seed(writer));

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<PostBudResult> bud({
      String actor = _budder,
      String commandId = 'cmd-archive-1',
      bool closePost = false,
      List<PostBudInvitee> invitees = const [
        PostBudInvitee(userId: _invitee, note: 'You know the area'),
      ],
    }) => buds.budFromPost(
      actorUserId: actor,
      postId: _post,
      clientCommandId: commandId,
      title: 'Move the piano',
      description: 'Saturday, two people',
      invitees: invitees,
      closePost: closePost,
    );

    /// The author ends the open Post on their own, before anyone buds.
    Future<void> closeByAuthor() => uow.run(
      actorUserId: _author,
      action: () => postClose.closeByAuthor(postId: _post, actorId: _author),
    );

    Future<int> status() async =>
        (await writer.execute(
              "SELECT status FROM public.beacon WHERE id = '$_post'",
            )).single.single!
            as int;

    Future<List<Map<String, Object?>>> postClosedNotices() async {
      final rows = await writer.execute('''
SELECT system_payload FROM public.beacon_room_message
WHERE beacon_id = '$_post'
  AND system_message_kind = ${BeaconRoomSystemMessageKind.postClosed}
''');
      return [for (final r in rows) _json(r.single)];
    }

    Future<List<Map<String, Object?>>> childCreatedNotices() async {
      final rows = await writer.execute('''
SELECT system_payload FROM public.beacon_room_message
WHERE beacon_id = '$_post'
  AND hierarchy_notice_identity LIKE 'child_created:%'
''');
      return [for (final r in rows) _json(r.single)];
    }

    Future<List<String>> lifecycleReasons() async {
      final rows = await writer.execute('''
SELECT diff FROM public.beacon_activity_event
WHERE beacon_id = '$_post'
  AND type = ${BeaconActivityEventTypeBits.beaconLifecycleChanged}
ORDER BY created_at
''');
      return [for (final r in rows) _json(r.single)['reason']! as String];
    }

    Future<Map<String, int>> childrenAndInvites(String childId) async {
      final children = await writer.execute(
        Sql.named(
          'SELECT count(*)::int FROM public.beacon '
          'WHERE parent_beacon_id = @p AND id = @c AND kind = 0',
        ),
        parameters: {'p': _post, 'c': childId},
      );
      final invites = await writer.execute(
        Sql.named(
          'SELECT count(*)::int FROM public.beacon_author_invite '
          'WHERE beacon_id = @c AND invitee_id = @i AND source_post_id = @p',
        ),
        parameters: {'p': _post, 'c': childId, 'i': _invitee},
      );
      return {
        'children': children.single.single! as int,
        'invites': invites.single.single! as int,
      };
    }

    Future<int> beaconCount() async =>
        (await writer.execute(
              'SELECT count(*)::int FROM public.beacon',
            )).single.single!
            as int;

    group('a Post its author closed', () {
      setUp(closeByAuthor);

      test('a member buds a Request from it with the invitations and one '
          'child-creation notice', () async {
        final result = await bud();

        expect(result.outcome, 'created');
        final childId = result.childBeaconId!;
        expect(await childrenAndInvites(childId), {
          'children': 1,
          'invites': 1,
        });
        final created = await childCreatedNotices();
        expect(created, hasLength(1));
        expect(created.single['title'], 'Move the piano');
        expect(created.single['invitedCount'], 1);
      });

      test('the Post stays closed with its original reason and gets no second '
          'closed notice', () async {
        await bud();

        expect(await status(), 6);
        expect(await lifecycleReasons(), ['postClosedByAuthor']);
        final closed = await postClosedNotices();
        expect(closed, hasLength(1));
        expect(closed.single['reason'], 'closedByAuthor');
        expect(closed.single.containsKey('childBeaconId'), isFalse);
      });

      test('the author budding with closePost leaves the Post closed as it '
          'was, with the Request created', () async {
        final result = await bud(
          actor: _author,
          commandId: 'cmd-archive-author',
          closePost: true,
        );

        expect(result.outcome, 'created');
        expect(await childrenAndInvites(result.childBeaconId!), {
          'children': 1,
          'invites': 1,
        });
        expect(await status(), 6);
        expect(await lifecycleReasons(), ['postClosedByAuthor']);
        final closed = await postClosedNotices();
        expect(closed, hasLength(1));
        expect(closed.single['reason'], 'closedByAuthor');
        final created = await childCreatedNotices();
        expect(created, hasLength(1));
        expect(created.single['title'], 'Move the piano');
        expect(created.single['invitedCount'], 1);
      });

      test('a member who is not the author buds with closePost: the Request '
          'is created and the Post stays closed as it was', () async {
        final result = await bud(closePost: true);

        expect(result.outcome, 'created');
        expect(await childrenAndInvites(result.childBeaconId!), {
          'children': 1,
          'invites': 1,
        });
        expect(await status(), 6);
        expect(await lifecycleReasons(), ['postClosedByAuthor']);
        final closed = await postClosedNotices();
        expect(closed, hasLength(1));
        expect(closed.single['reason'], 'closedByAuthor');
        expect(closed.single.containsKey('childBeaconId'), isFalse);
        final created = await childCreatedNotices();
        expect(created, hasLength(1));
        expect(created.single['title'], 'Move the piano');
        expect(created.single['invitedCount'], 1);
      });

      test(
        'a replayed bud returns the stored result and adds nothing',
        () async {
          final first = await bud();
          final beaconsBefore = await beaconCount();

          final second = await bud();

          expect(second.childBeaconId, first.childBeaconId);
          expect(await beaconCount(), beaconsBefore);
          expect(await childCreatedNotices(), hasLength(1));
          expect(await postClosedNotices(), hasLength(1));
        },
      );

      test('a non-member is refused and nothing is created', () async {
        final before = await beaconCount();

        await expectLater(
          bud(actor: _outsider, invitees: const []),
          throwsA(isA<BeaconChildCreateForbiddenException>()),
        );

        expect(await beaconCount(), before);
        expect(await childCreatedNotices(), isEmpty);
      });
    });

    group('an expired Post that is still open', () {
      setUp(() async {
        await writer.execute('''
UPDATE public.beacon
SET published_at = now() - interval '4 hours',
    expires_at = now() - interval '1 hour'
WHERE id = '$_post'
''');
      });

      test(
        'the author budding with closePost closes it with reason budded',
        () async {
          final result = await bud(actor: _author, closePost: true);

          expect(await childrenAndInvites(result.childBeaconId!), {
            'children': 1,
            'invites': 1,
          });
          expect(await status(), 6);
          expect(await lifecycleReasons(), ['directClose']);
          final closed = await postClosedNotices();
          expect(closed, hasLength(1));
          expect(closed.single['reason'], 'budded');
          expect(closed.single['childBeaconId'], result.childBeaconId);
          final created = await childCreatedNotices();
          expect(created, hasLength(1));
          expect(created.single['title'], 'Move the piano');
          expect(created.single['invitedCount'], 1);
        },
      );
    });

    group('a Post that cannot be budded from', () {
      test('a deleted Post is refused and nothing is created', () async {
        await writer.execute(
          'UPDATE public.beacon SET status = '
          '${BeaconStatus.deleted.smallintValue} '
          "WHERE id = '$_post'",
        );
        final before = await beaconCount();

        await expectLater(bud(), throwsA(isA<PostNotOpenException>()));

        expect(await beaconCount(), before);
        expect(await childCreatedNotices(), isEmpty);
      });

      test('a non-member is refused on a Post that is still open', () async {
        await expectLater(
          bud(actor: _outsider, invitees: const []),
          throwsA(isA<BeaconChildCreateForbiddenException>()),
        );
      });
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
  public.attention_channel_delivery,
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon_child_commands,
  public.beacon_promotions,
  public.beacon_bud_observer,
  public.beacon_author_invite,
  public.beacon_activity_event,
  public.post_first_response,
  public.user_availability,
  public.user_block,
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
      parameters: {'id': _users[i], 'key': pgTestPublicKey('barc1', i + 1)},
    );
  }
  // An open Post with a day left to live.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false,
        now() - interval '1 hour', now() + interval '23 hours')
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, created_at)
VALUES
  ('Fbarc1e01', '$_post', '$_author', '$_budder',
   now() - interval '50 minutes'),
  ('Fbarc1e02', '$_post', '$_author', '$_invitee',
   now() - interval '40 minutes')
''');
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

/// Forward visibility of the budder: only [visible] peers pass.
final class _Visibility extends Fake implements PersonVisibilityRepositoryPort {
  _Visibility(this.visible);

  final Set<String> visible;

  @override
  Future<Set<String>> personVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  }) async => peerIds.where(visible.contains).toSet();
}

@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dismissible_sql.dart';
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
import 'package:tentura_server/domain/entity/post_bud_invite_candidate.dart';
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

/// Budding C3: `beaconBudFromPost` and `postBudInviteCandidates`
/// (`PostBudCase`, Arch §4.2) with real repositories and real attention
/// dispatch.
///
/// `_post` (author `_author`) admits everyone below through forward edges
/// except `_outsider`:
/// - `_budder` buds from their own message `_budderMsg`;
/// - `_warm` is a first responder (and writes), `_cold` is forward-visible
///   to the budder, `_hidden` is not (and arrived through the budder);
/// - `_paused` is availability-paused, `_blocked` is blocked with the
///   budder, `_invited` already holds a pending invite from the budder for
///   this Post.
const _author = 'Upbud3author';
const _budder = 'Upbud3budder';
const _warm = 'Upbud3warm01';
const _cold = 'Upbud3cold01';
const _hidden = 'Upbud3hidden';
const _paused = 'Upbud3paused';
const _blocked = 'Upbud3blockd';
const _invited = 'Upbud3invitd';
const _outsider = 'Upbud3outsdr';
const _users = [
  _author,
  _budder,
  _warm,
  _cold,
  _hidden,
  _paused,
  _blocked,
  _invited,
  _outsider,
];

const _post = 'Bpbud3post01';
const _otherChild = 'Bpbud3other1';

const _rootMsg = 'Rpbud3root01';
const _budderMsg = 'Rpbud3budd01';
const _warmMsg = 'Rpbud3warm01';

const _edgeToWarm = 'Fpbud3e02';
const _edgeToCold = 'Fpbud3e03';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_BUD_CASE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_bud_case',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('PostBudCase', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late PostBudCase buds;
    late BudAnchorSweepCase anchorSweep;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      final env = target.databaseEnv;
      final logger = Logger('PostBudCasePgTest');
      final attention = TransactionalAttentionCase(
        MutatingUnitOfWork(database),
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
        _Visibility({_cold, _budder}),
      );
      final beacons = BeaconRepository(database);
      final anchorSweepPort = BudAnchorSweepRepository(database);
      anchorSweep = BudAnchorSweepCase(
        anchorSweepPort,
        AnchorInheritOperation(
          ConstellationAnchorRepository(database),
          anchorSweepPort,
        ),
        env: env,
        logger: logger,
      );
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
        PostCloseOperation(beacons),
        anchorSweep,
      );
    });

    setUp(() async {
      await _seed(writer);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<PostBudResult> bud({
      String actor = _budder,
      String source = _budderMsg,
      String commandId = 'cmd-c3-1',
      String title = 'Move the piano',
      List<PostBudInvitee> invitees = const [],
      bool closePost = false,
    }) => buds.budFromPost(
      actorUserId: actor,
      postId: _post,
      sourceMessageId: source,
      clientCommandId: commandId,
      title: title,
      description: 'Saturday, two people',
      invitees: invitees,
      closePost: closePost,
    );

    Map<String, PostBudInviteOutcome> outcomes(PostBudResult result) => {
      for (final i in result.invitees) i.userId: i.outcome,
    };

    test('happy path: child, observers, invites, edges, pins, one notice, '
        'receipts only to invitees', () async {
      final result = await bud(
        invitees: const [
          PostBudInvitee(userId: _warm, note: '  You have a van  '),
          PostBudInvitee(userId: _cold),
          PostBudInvitee(userId: _author, note: ''),
        ],
      );

      expect(result.outcome, 'created');
      // After commit, the anchor inheritance sweep is nudged (C8).
      expect(anchorSweep.consumeNudge(), isTrue);
      final child = result.childBeaconId!;
      expect(
        [for (final i in result.invitees) i.userId],
        [
          _warm,
          _cold,
          _author,
        ],
      );
      expect(
        result.invitees.map((i) => i.outcome),
        everyElement(PostBudInviteOutcome.invited),
      );

      final childRow = await writer.execute(
        Sql.named(
          'SELECT parent_beacon_id, is_discoverable, title FROM public.beacon '
          'WHERE id = @c',
        ),
        parameters: {'c': child},
      );
      expect(childRow.single[0], _post);
      expect(childRow.single[1], isFalse);
      expect(childRow.single[2], 'Move the piano');

      // Observers: E(P) minus the budder and minus users blocked with them.
      expect(await _observers(writer, child), {
        _author,
        _warm,
        _cold,
        _hidden,
        _paused,
        _invited,
      });

      // Invites: provenance, note only on the invite.
      final invites = await _invites(writer, child);
      expect(invites.keys.toSet(), {_warm, _cold, _author});
      expect(invites[_warm]!.warm, isTrue);
      expect(invites[_author]!.warm, isTrue);
      expect(invites[_cold]!.warm, isFalse);
      expect(invites[_warm]!.arrival, _edgeToWarm);
      expect(invites[_cold]!.arrival, _edgeToCold);
      expect(invites[_author]!.arrival, isNull);
      expect(invites[_warm]!.note, 'You have a van');
      expect(invites[_cold]!.note, isNull);
      expect(invites[_author]!.note, isNull);
      for (final invite in invites.values) {
        expect(invite.status, 0);
        expect(invite.inviter, _budder);
        expect(invite.sourcePost, _post);
      }

      // Delivery edges budder -> invitee on the child, no parent edge, empty
      // note, sweep exemption only for warm invitees.
      final edges = await _childEdges(writer, child);
      expect(edges.keys.toSet(), {_warm, _cold, _author});
      for (final entry in edges.entries) {
        expect(entry.value.sender, _budder);
        expect(entry.value.parentEdgeId, isNull);
        expect(entry.value.note, '');
        expect(entry.value.id, invites[entry.key]!.forwardEdgeId);
      }
      expect(edges[_warm]!.exempt, isTrue);
      expect(edges[_author]!.exempt, isTrue);
      expect(edges[_cold]!.exempt, isFalse);

      // The invitee's inbox row is pinned in «Для вас».
      for (final invitee in [_warm, _cold, _author]) {
        expect(
          await _eligiblePinned(writer, invitee),
          contains(child),
          reason: invitee,
        );
      }

      // One notice with the title snapshot and the invite count.
      final notices = await _childCreatedNotices(writer);
      expect(notices, hasLength(1));
      expect(notices.single['title'], 'Move the piano');
      expect(notices.single['invitedCount'], 3);

      // Receipts: one authorInviteReceived per invitee, none to anyone else.
      final receipts = await _receipts(writer);
      expect(receipts.map((r) => r.account).toSet(), {
        _warm,
        _cold,
        _author,
      });
      expect(receipts, hasLength(3));
      for (final receipt in receipts) {
        expect(receipt.beaconId, child);
        expect(receipt.kind, 'authorInviteReceived');
        expect(
          receipt.sourceEventKey,
          'author_invite:${invites[receipt.account]!.id}',
        );
      }

      // The Post stays open without closePost.
      expect(await _postStatus(writer), BeaconStatus.open.smallintValue);
    });

    test('replay returns an identical result and writes no new rows', () async {
      const invitees = [
        PostBudInvitee(userId: _warm, note: 'van'),
        PostBudInvitee(userId: _hidden),
      ];
      final first = await bud(invitees: invitees);
      final before = await _rowCounts(writer);

      final second = await bud(invitees: invitees);

      expect(second.outcome, first.outcome);
      expect(second.childBeaconId, first.childBeaconId);
      expect(outcomes(second), outcomes(first));
      expect(await _rowCounts(writer), before);
    });

    test('replay works after closePost', () async {
      const invitees = [PostBudInvitee(userId: _warm)];
      final first = await bud(
        actor: _author,
        source: _rootMsg,
        invitees: invitees,
        closePost: true,
      );
      expect(await _postStatus(writer), BeaconStatus.closed.smallintValue);

      final second = await bud(
        actor: _author,
        source: _rootMsg,
        invitees: invitees,
        closePost: true,
      );

      expect(second.childBeaconId, first.childBeaconId);
      expect(outcomes(second), outcomes(first));
    });

    test(
      'closePost closes the Post with a notice pointing at the child',
      () async {
        final result = await bud(
          actor: _author,
          source: _rootMsg,
          closePost: true,
        );
        expect(await _postStatus(writer), BeaconStatus.closed.smallintValue);
        final closed = await writer.execute(
          Sql.named(
            "SELECT system_payload->>'childBeaconId' "
            'FROM public.beacon_room_message '
            'WHERE beacon_id = @p AND system_message_kind = 5',
          ),
          parameters: {'p': _post},
        );
        expect(closed.single[0], result.childBeaconId);
        expect(await _childCreatedNotices(writer), hasLength(1));
      },
    );

    // #666: the two notices of one bud share the transaction's now(); the
    // «closed» one must still come after «made the request».
    test('the closed notice comes after the made-the-request notice', () async {
      await bud(actor: _author, source: _rootMsg, closePost: true);
      final rows = await writer.execute(
        Sql.named(
          'SELECT system_message_kind FROM public.beacon_room_message '
          'WHERE beacon_id = @p AND system_message_kind IS NOT NULL '
          'ORDER BY created_at DESC, id DESC LIMIT 2',
        ),
        parameters: {'p': _post},
      );
      // Newest first: the close notice (kind 5), then the bud notice.
      expect(rows.first[0], 5);
      expect(rows.last[0], isNot(5));
    });

    // #666: a member who did not start the Post cannot close it; the whole
    // bud is refused, so no Request is left behind either.
    test('a member who is not the Post author cannot close it', () async {
      final before = await _rowCounts(writer);
      await expectLater(
        bud(closePost: true),
        throwsA(isA<BeaconChildCreateForbiddenException>()),
      );
      expect(await _postStatus(writer), BeaconStatus.open.smallintValue);
      expect(await _rowCounts(writer), before);

      // The same member may still bud without closing it.
      final result = await bud(commandId: 'cmd-c3-2');
      expect(result.childBeaconId, isNotNull);
      expect(await _postStatus(writer), BeaconStatus.open.smallintValue);
    });

    test(
      'a different input under the same clientCommandId conflicts',
      () async {
        await bud(invitees: const [PostBudInvitee(userId: _warm)]);
        await expectLater(
          bud(invitees: const [PostBudInvitee(userId: _cold)]),
          throwsA(isA<BeaconChildCommandConflictException>()),
        );
        await expectLater(
          bud(
            invitees: const [PostBudInvitee(userId: _warm)],
            closePost: true,
          ),
          throwsA(isA<BeaconChildCommandConflictException>()),
        );
      },
    );

    test('per-invitee failures do not fail the bud', () async {
      final result = await bud(
        invitees: const [
          PostBudInvitee(userId: _hidden),
          PostBudInvitee(userId: _paused),
          PostBudInvitee(userId: _blocked),
          PostBudInvitee(userId: _invited),
          PostBudInvitee(userId: _outsider),
          PostBudInvitee(userId: _budder),
          PostBudInvitee(userId: _warm),
          PostBudInvitee(userId: _warm),
          PostBudInvitee(userId: '  '),
        ],
      );

      expect(outcomes(result), {
        _hidden: PostBudInviteOutcome.notEligible,
        _paused: PostBudInviteOutcome.recipientPaused,
        _blocked: PostBudInviteOutcome.blocked,
        _invited: PostBudInviteOutcome.alreadyInvited,
        _outsider: PostBudInviteOutcome.notEligible,
        _budder: PostBudInviteOutcome.notEligible,
        _warm: PostBudInviteOutcome.invited,
      });
      expect(result.invitees, hasLength(7));
      final child = result.childBeaconId!;
      expect((await _invites(writer, child)).keys, [_warm]);
      expect((await _childEdges(writer, child)).keys, [_warm]);
      expect((await _childCreatedNotices(writer)).single['invitedCount'], 1);
      expect((await _receipts(writer)).map((r) => r.account), [_warm]);
    });

    test('the Post author may bud from the root message', () async {
      final result = await bud(
        actor: _author,
        source: _rootMsg,
        invitees: const [PostBudInvitee(userId: _budder)],
      );
      expect(outcomes(result), {_budder: PostBudInviteOutcome.invited});
      final invites = await _invites(writer, result.childBeaconId!);
      expect(invites[_budder]!.warm, isFalse);
    });

    test("budding from someone else's message is rejected", () async {
      await expectLater(
        bud(source: _warmMsg),
        throwsA(isA<BudSourceNotOwnMessageException>()),
      );
      expect(await _invitesCount(writer), 1, reason: 'only the seeded one');
    });

    test('a draft Post is rejected', () async {
      await writer.execute(
        'UPDATE public.beacon SET status = '
        '${BeaconStatus.draft.smallintValue} '
        "WHERE id = '$_post'",
      );
      await expectLater(
        bud(invitees: const [PostBudInvitee(userId: _warm)]),
        throwsA(isA<PostNotOpenException>()),
      );
    });

    group('inviteCandidates', () {
      test('lists E(P) minus the caller, writers first', () async {
        final candidates = await buds.inviteCandidates(
          actorUserId: _budder,
          postId: _post,
        );
        final ids = [for (final c in candidates) c.userId];
        expect(ids.toSet(), {
          _author,
          _warm,
          _cold,
          _hidden,
          _paused,
          _blocked,
          _invited,
        });
        // Writers (the author and _warm) first, then by id.
        expect(ids.take(2), [_author, _warm]);
        expect(ids.skip(2).toList(), [..._sorted(ids.skip(2))]);

        final byId = {for (final c in candidates) c.userId: c};
        expect(byId[_warm]!.warm, isTrue);
        expect(byId[_warm]!.reason, PostBudInviteReason.eligible);
        expect(byId[_warm]!.pretick, isTrue, reason: 'replied to the budder');
        expect(byId[_hidden]!.reason, PostBudInviteReason.notVisible);
        expect(byId[_blocked]!.reason, PostBudInviteReason.blocked);
        expect(byId[_paused]!.reason, PostBudInviteReason.recipientPaused);
        expect(byId[_invited]!.reason, PostBudInviteReason.alreadyInvited);
      });

      test('hides viaUserId when it is the caller', () async {
        final candidates = await buds.inviteCandidates(
          actorUserId: _budder,
          postId: _post,
        );
        final byId = {for (final c in candidates) c.userId: c};
        expect(byId[_hidden]!.viaUserId, isNull, reason: 'arrived via budder');
        expect(byId[_cold]!.viaUserId, _author);
        expect(byId[_author]!.viaUserId, isNull);
      });

      test('a non-member is forbidden', () async {
        await expectLater(
          buds.inviteCandidates(actorUserId: _outsider, postId: _post),
          throwsA(isA<BeaconChildCreateForbiddenException>()),
        );
      });
    });
  });
}

List<String> _sorted(Iterable<String> ids) => ids.toList()..sort();

Future<Set<String>> _observers(Connection writer, String child) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT user_id FROM public.beacon_bud_observer WHERE beacon_id = @c',
    ),
    parameters: {'c': child},
  );
  return {for (final r in rows) r[0]! as String};
}

typedef _InviteRow = ({
  String id,
  String inviter,
  String? sourcePost,
  String? forwardEdgeId,
  String? arrival,
  bool warm,
  String? note,
  int status,
});

Future<Map<String, _InviteRow>> _invites(
  Connection writer,
  String child,
) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT invitee_id, id, inviter_id, source_post_id, forward_edge_id, '
      'arrival_post_edge_id, warm, note, status '
      'FROM public.beacon_author_invite WHERE beacon_id = @c '
      'ORDER BY invitee_id',
    ),
    parameters: {'c': child},
  );
  return {
    for (final r in rows)
      r[0]! as String: (
        id: r[1]! as String,
        inviter: r[2]! as String,
        sourcePost: r[3] as String?,
        forwardEdgeId: r[4] as String?,
        arrival: r[5] as String?,
        warm: r[6]! as bool,
        note: r[7] as String?,
        status: r[8]! as int,
      ),
  };
}

Future<int> _invitesCount(Connection writer) async {
  final rows = await writer.execute(
    'SELECT count(*)::int FROM public.beacon_author_invite',
  );
  return rows.single.single! as int;
}

typedef _EdgeRow = ({
  String id,
  String sender,
  String? parentEdgeId,
  String note,
  bool exempt,
});

Future<Map<String, _EdgeRow>> _childEdges(
  Connection writer,
  String child,
) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT recipient_id, id, sender_id, parent_edge_id, note, '
      'contact_sweep_exempt FROM public.beacon_forward_edge '
      'WHERE beacon_id = @c ORDER BY recipient_id',
    ),
    parameters: {'c': child},
  );
  return {
    for (final r in rows)
      r[0]! as String: (
        id: r[1]! as String,
        sender: r[2]! as String,
        parentEdgeId: r[3] as String?,
        note: r[4]! as String,
        exempt: r[5]! as bool,
      ),
  };
}

Future<Set<String>> _eligiblePinned(Connection writer, String viewer) async {
  final rows = await writer.execute(
    'WITH ${AttentionDismissibleSql.prelude} '
    'SELECT beacon_id FROM eligible_pinned',
    parameters: [viewer],
  );
  return {for (final r in rows) r[0]! as String};
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

typedef _Receipt = ({
  String account,
  String? beaconId,
  String kind,
  String sourceEventKey,
});

Future<List<_Receipt>> _receipts(Connection writer) async {
  final rows = await writer.execute(
    'SELECT account_id, beacon_id, kind, source_event_key '
    'FROM public.notification_outbox ORDER BY account_id',
  );
  return [
    for (final r in rows)
      (
        account: r[0]! as String,
        beaconId: r[1] as String?,
        kind: r[2]! as String,
        sourceEventKey: r[3]! as String,
      ),
  ];
}

Future<int> _postStatus(Connection writer) async {
  final rows = await writer.execute(
    "SELECT status FROM public.beacon WHERE id = '$_post'",
  );
  return rows.single.single! as int;
}

Future<List<int>> _rowCounts(Connection writer) async {
  final rows = await writer.execute('''
SELECT
  (SELECT count(*)::int FROM public.beacon),
  (SELECT count(*)::int FROM public.beacon_bud_observer),
  (SELECT count(*)::int FROM public.beacon_author_invite),
  (SELECT count(*)::int FROM public.beacon_forward_edge),
  (SELECT count(*)::int FROM public.beacon_room_message),
  (SELECT count(*)::int FROM public.notification_outbox),
  (SELECT count(*)::int FROM public.inbox_item)
''');
  return [for (final v in rows.single) v! as int];
}

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
      parameters: {'id': _users[i], 'key': pgTestPublicKey('pbud3', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now())
''');
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_otherChild', '$_budder', 'Earlier', '', 0, now())
''');

  // Forward edges admit the recipients (m0210); later edges are younger.
  var minutesAgo = 100;
  Future<void> edge(String id, String sender, String recipient) =>
      writer.execute('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, created_at)
VALUES ('$id', '$_post', '$sender', '$recipient',
        now() - interval '${minutesAgo--} minutes')
''');
  await edge('Fpbud3e01', _author, _budder);
  await edge(_edgeToWarm, _author, _warm);
  await edge(_edgeToCold, _author, _cold);
  await edge('Fpbud3e04', _budder, _hidden);
  await edge('Fpbud3e05', _author, _paused);
  await edge('Fpbud3e06', _author, _blocked);
  await edge('Fpbud3e07', _author, _invited);

  await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_blocked', '$_budder', '$_blocked')
''');
  await writer.execute('''
INSERT INTO public.user_availability (user_id, resume_on)
VALUES ('$_paused', public.utc_today() + 3)
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, reply_to_message_id)
VALUES
  ('$_rootMsg', '$_post', '$_author', 'Who has a van?', NULL),
  ('$_budderMsg', '$_post', '$_budder', 'I could organise the move', NULL),
  ('$_warmMsg', '$_post', '$_warm', 'I have a van', '$_budderMsg')
''');
  await writer.execute('''
INSERT INTO public.post_first_response (beacon_id, user_id, source_kind, source_id)
VALUES ('$_post', '$_warm', 1, '$_warmMsg')
''');
  await writer.execute('''
INSERT INTO public.beacon_author_invite
  (id, beacon_id, inviter_id, invitee_id, source_post_id, warm, status)
VALUES ('BIpbud3inv01', '$_otherChild', '$_budder', '$_invited', '$_post',
        false, 0)
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

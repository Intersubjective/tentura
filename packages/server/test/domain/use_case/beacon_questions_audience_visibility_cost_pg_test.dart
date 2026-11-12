@Tags(['pg', 'repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/sql/request_unread_sql.dart';
import 'package:tentura_server/data/repository/beacon_lobby_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';

class _FakeFactCards extends Fake implements BeaconFactCardRepositoryPort {}

class _FakeImages extends Fake implements ImageRepositoryPort {}

class _FakeTasks extends Fake implements TaskRepositoryPort {}

class _FakeRemoteStorage extends Fake implements RemoteStoragePort {}

class _FakePolling extends Fake implements PollingRepositoryPort {}

class _FakeUploadQuota extends Fake implements UploadQuotaRepositoryPort {}

/// Records whom each Questions notice would reach.
final class _RecordingIntents extends Fake implements AttentionIntentCase {
  final mentioned = <String>{};
  final directed = <String>{};

  static const _intent = AttentionDispatchIntent(
    eventType: AttentionEventType.relayReceived,
    sourceEventKey: 'test',
    actorUserId: null,
    priority: NotificationPriority.high,
    kind: NotificationKind.needsMe,
    title: '',
    body: '',
    actionUrl: '',
    collapseKey: '',
    recipients: [],
  );

  @override
  Future<AttentionDispatchIntent> roomMentioned({
    required String beaconId,
    required String messageId,
    required String actorUserId,
    required Set<String> recipientUserIds,
    required String excerpt,
    required String sourceEventKey,
    String? threadItemId,
    bool questionsScope = false,
  }) async {
    mentioned.addAll(recipientUserIds);
    return _intent;
  }

  @override
  Future<AttentionDispatchIntent> roomMessagePosted({
    required String beaconId,
    required String messageId,
    required String actorUserId,
    required Set<String> recipientUserIds,
    required String excerpt,
    required String sourceEventKey,
    String? threadItemId,
    bool questionsScope = false,
  }) async {
    directed.addAll(recipientUserIds);
    return _intent;
  }
}

final class _NoopDispatch implements AttentionDispatchPort {
  @override
  Future<void> record(AttentionDispatchIntent intent) async {}
}

/// Cost of Request Questions on a discoverable Request: the discoverable
/// standing (mutual visibility with the author, a MeritRank peer-set lookup
/// per person) is only worth computing for someone with no cheaper standing.
/// Forward recipients already stand through their forward edge, so a
/// Questions message must not compute a visible peer set for each of them.
///
/// Calls are counted by wrapping `person_visible_peer_ids_tx` in this
/// disposable database with a counting function of the same signature (the
/// original stays callable under another name); no timing is asserted.
/// That function is the contract here: it is the per-person MeritRank
/// peer-set lookup behind the shared mutual-visibility predicate
/// (`person_are_mutually_visible_cached`) that the content wall's
/// discoverability clause uses, so it is the cost being counted however the
/// Questions policy reaches the wall.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_QUESTIONS_COST_TEST_DB',
    defaultNamePrefix: 'tentura_test_beacon_questions_cost',
  );
  final skipReason = await pgSkipReason(target);

  const beaconId = 'Bqcostreq001';
  const author = 'Uqcostauthor';
  const stranger = 'Uqcoststrang';
  final recipients = [
    for (var i = 0; i < 24; i++) 'Uqcostrcp${i.toString().padLeft(3, '0')}',
  ];

  group('Questions on a discoverable Request with many forward recipients', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late BeaconRoomCase rooms;
    late _RecordingIntents intents;

    Future<void> sql(String statement) => writer.execute(statement);

    /// Peer-set computations per viewer since the last reset.
    Future<Map<String, int>> peerSetCalls() async => {
      for (final r in await writer.execute(
        'SELECT viewer_id, count(*)::integer '
        'FROM public.test_peer_set_calls GROUP BY viewer_id',
      ))
        r[0]! as String: r[1]! as int,
    };

    setUpAll(() async {
      if (skipReason != null) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      // Install the counting hook before any application connection plans
      // a statement that reaches the peer-set function.
      await sql(
        'CREATE TABLE public.test_peer_set_calls '
        '(viewer_id text, ctx text, called_at timestamptz DEFAULT now())',
      );
      await sql(
        'ALTER FUNCTION public.person_visible_peer_ids_tx(text, text) '
        'RENAME TO test_counted_person_visible_peer_ids_tx',
      );
      await sql(r'''
CREATE FUNCTION public.person_visible_peer_ids_tx(viewer_id text, ctx text)
RETURNS text[]
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO public.test_peer_set_calls (viewer_id, ctx)
  VALUES (viewer_id, ctx);
  RETURN public.test_counted_person_visible_peer_ids_tx(viewer_id, ctx);
END;
$$
''');
      final shipped =
          jsonDecode(
                File(
                  'test/data/database/fixtures/questions_shipped_migrations.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      await sql(
        (shipped['0300'] as List).first.toString().replaceFirst(
          'public.questions_access_levels(',
          'public.test_shipped_questions_access_levels(',
        ),
      );
      db = TenturaDb(target.databaseEnv);
    });

    tearDownAll(() async {
      if (skipReason != null) return;
      await db.close();
      await sql(
        'DROP FUNCTION public.test_shipped_questions_access_levels(text, text[])',
      );
      await sql(
        'DROP FUNCTION IF EXISTS public.person_visible_peer_ids_tx(text, text)',
      );
      await sql(
        'ALTER FUNCTION '
        'public.test_counted_person_visible_peer_ids_tx(text, text) '
        'RENAME TO person_visible_peer_ids_tx',
      );
      await sql('DROP TABLE IF EXISTS public.test_peer_set_calls');
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      if (skipReason != null) return;
      intents = _RecordingIntents();
      rooms = BeaconRoomCase(
        BeaconRoomRepository(db),
        CoordinationItemRepository(db),
        _FakeFactCards(),
        _FakeImages(),
        _FakeTasks(),
        _FakeRemoteStorage(),
        _FakePolling(),
        _FakeUploadQuota(),
        FakeUserBlockRepository(),
        PassThroughMutatingUnitOfWork(),
        FakeBeaconHierarchyRepository(),
        const ProductionDiscussionProductPolicy(),
        attentionIntents: intents,
        attention: TransactionalAttentionCase(
          PassThroughMutatingUnitOfWork(),
          _NoopDispatch(),
        ),
        lobby: BeaconLobbyRepository(db),
        env: Env(environment: Environment.test),
        logger: Logger('beacon_questions_audience_visibility_cost_pg_test'),
      );
      await sql(
        'TRUNCATE TABLE public.beacon_room_message, public.beacon_room_seen, '
        'public.coordination_item, public.beacon_help_offer, '
        'public.beacon_forward_edge, public.beacon_participant, '
        'public.beacon_steward, public.beacon_lobby_ban, public.user_block, '
        'public.beacon, public."user" CASCADE',
      );
      final users = [author, stranger, ...recipients];
      await sql(
        'INSERT INTO public."user" (id, display_name, handle, public_key) '
        'VALUES ${[for (final u in users) "('$u', '${u.substring(2)}', '${u.substring(2)}', 'k$u')"].join(', ')}',
      );
      await sql(
        'INSERT INTO public.beacon (id, user_id, title, description, status, '
        'kind, is_discoverable, published_at, created_at, updated_at) VALUES '
        "('$beaconId', '$author', 'Moving day', 'desc', 0, 0, true, "
        "'2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', "
        "'2026-01-01T00:00:00Z')",
      );
      await sql(
        'INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, '
        'recipient_id) VALUES '
        '${[for (final r in recipients) "('$beaconId', '$author', '$r')"].join(', ')}',
      );
      await sql('TRUNCATE TABLE public.test_peer_set_calls');
    });

    test('a Questions message computes no visible peer set for any forward '
        'recipient', () async {
      final lobbyId =
          (await rooms.beaconLobby(
                beaconId: beaconId,
                userId: author,
              ))['lobbyId']!
              as String;
      await sql('TRUNCATE TABLE public.test_peer_set_calls');

      // Mentions resolve against the whole Questions audience, and the
      // realtime hint of the insert fans out to it as well.
      final mentionedRecipients = recipients.take(3).toList();
      await rooms.createMessage(
        beaconId: beaconId,
        userId: author,
        body:
            'Ask me anything about the move '
            '${mentionedRecipients.map((r) => '@${r.substring(2)}').join(' ')}',
        threadItemId: lobbyId,
      );

      // Positive control: the audience was resolved for this message.
      expect(intents.mentioned, containsAll(mentionedRecipients));
      final calls = await peerSetCalls();
      expect(
        {
          for (final r in recipients)
            if ((calls[r] ?? 0) > 0) r: calls[r],
        },
        isEmpty,
        reason: 'peer-set calls per forward recipient: $calls',
      );
    });

    test(
      'fresh databases install the registered Questions standing upgrade',
      () async {
        // setUpDisposablePgWriter migrates a fresh registry-hashed template
        // before cloning it; a changed registry cannot reuse an older schema.
        final upgrades = migrationsForTesting
            .where(
              (migration) =>
                  migration.version.compareTo('0308') > 0 &&
                  migration.statements.any(
                    (statement) => statement.contains(
                      'CREATE OR REPLACE FUNCTION public.questions_access_levels(',
                    ),
                  ),
            )
            .toList();
        expect(
          upgrades,
          isNotEmpty,
          reason:
              'fresh and already upgraded databases need the same policy upgrade',
        );
        final applied = await writer.execute(
          'SELECT max(version) FROM public.schema_version',
        );
        expect(
          (applied.single.single! as String).compareTo(upgrades.last.version),
          greaterThanOrEqualTo(0),
        );
        final levels = await writer.execute(
          "SELECT user_id, access FROM public.questions_access_levels('$beaconId', "
          "ARRAY['$author', '$stranger'])",
        );
        expect(
          {for (final row in levels) row[0]: row[1]},
          {author: 2, stranger: 0},
        );
      },
    );

    group('Questions standing bypasses unnecessary discoverability lookups', () {
      for (final grant in [
        'a steward',
        'bud observers',
        'addressees with a bud snapshot',
        'addressees with parent stewardship',
        'addressees with parent membership',
      ]) {
        test('mentions reach $grant without peer-set lookups', () async {
          const parent = 'Bqcostparent';
          // beacon_steward has a unique beacon_id: a Request has one
          // steward. Other grants exercise several simultaneous viewers.
          final members = recipients
              .take(
                grant == 'a steward' || grant.contains('stewardship') ? 1 : 4,
              )
              .toList();
          // Replace the forward standing from the shared fixture. These
          // viewers must reach Questions through the cheaper grant itself.
          await sql('DELETE FROM public.beacon_forward_edge');
          final parentIsRequest = grant.contains('parent');
          await sql(
            'INSERT INTO public.beacon '
            '(id, user_id, title, description, status, kind, is_discoverable, published_at) '
            "VALUES ('$parent', '$author', '', '', 0, "
            '${parentIsRequest ? 0 : 1}, false, now())',
          );
          await sql("DELETE FROM public.beacon WHERE id = '$beaconId'");
          await sql(
            'INSERT INTO public.beacon '
            '(id, user_id, title, description, status, kind, '
            'is_discoverable, published_at, parent_beacon_id) '
            "VALUES ('$beaconId', '$author', 'Moving day', '', 0, 0, "
            "true, now(), '$parent')",
          );
          for (final user in members) {
            if (grant == 'a steward' || grant.contains('stewardship')) {
              final scope = grant == 'a steward' ? beaconId : parent;
              await sql(
                'INSERT INTO public.beacon_steward (beacon_id, user_id) '
                "VALUES ('$scope', '$user')",
              );
            }
            if (grant == 'bud observers' || grant.contains('snapshot')) {
              await sql(
                'INSERT INTO public.beacon_bud_observer (beacon_id, user_id) '
                "VALUES ('$beaconId', '$user')",
              );
            }
            if (grant.startsWith('addressees')) {
              await sql(
                'INSERT INTO public.beacon_participant '
                '(beacon_id, user_id, role, status, room_access) '
                "VALUES ('$beaconId', '$user', 6, 0, 0)",
              );
            }
            if (grant.contains('membership')) {
              await sql(
                'INSERT INTO public.beacon_participant '
                '(beacon_id, user_id, role, status, room_access) '
                "VALUES ('$parent', '$user', 1, 0, 3)",
              );
            }
          }
          // Confirm that snapshot grants really refer to a live Post and
          // that the content wall accepts each viewer before measuring cost.
          final parentShape = await writer.execute(
            'SELECT kind, status, published_at IS NOT NULL FROM public.beacon '
            "WHERE id = '$parent'",
          );
          expect(parentShape.single, [if (parentIsRequest) 0 else 1, 0, true]);
          final lobby = await rooms.beaconLobby(
            beaconId: beaconId,
            userId: author,
          );
          await sql('TRUNCATE public.test_peer_set_calls');
          await rooms.createMessage(
            beaconId: beaconId,
            userId: author,
            body: members.map((u) => '@${u.substring(2)}').join(' '),
            threadItemId: lobby['lobbyId']! as String,
          );
          expect(intents.mentioned, containsAll(members));
          final calls = await peerSetCalls();

          // The optimization must preserve the policy, including its wall
          // and closed-state protections, rather than just skip evaluation.
          Future<void> expectParity(List<String> users) async {
            final rows = await writer.execute(
              Sql.named('''
SELECT current.user_id, current.access, shipped.access
FROM public.questions_access_levels(@beacon, @users::text[]) current
JOIN public.test_shipped_questions_access_levels(@beacon, @users::text[]) shipped
USING (user_id)
'''),
              parameters: {'beacon': beaconId, 'users': users},
            );
            expect(rows, hasLength(users.length));
            for (final row in rows) {
              expect(row[1], row[2], reason: 'shipped access for ${row[0]}');
            }
          }

          Future<void> expectAccess(int level) async {
            await expectParity(members);
            final rows = await writer.execute(
              Sql.named(
                'SELECT user_id, access FROM public.questions_access_levels( '
                '@beacon, @users::text[])',
              ),
              parameters: {'beacon': beaconId, 'users': members},
            );
            expect(
              {for (final row in rows) row[0]: row[1]},
              {
                for (final user in members) user: level,
              },
            );
          }

          for (final member in members) {
            final wall = await writer.execute(
              "SELECT public.beacon_can_read_content('$beaconId', '$member')",
            );
            expect(wall.single.single, isTrue);
          }
          await expectAccess(2);
          await sql(
            "UPDATE public.beacon SET status = 1 WHERE id = '$beaconId'",
          );
          await expectAccess(1);
          await sql(
            "UPDATE public.beacon SET status = 0 WHERE id = '$beaconId'",
          );
          for (final user in members) {
            await sql(
              'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
              "VALUES ('$author', '$user', '$author')",
            );
          }
          await expectAccess(0);
          intents.mentioned.clear();
          await sql('TRUNCATE public.test_peer_set_calls');
          await rooms.createMessage(
            beaconId: beaconId,
            userId: author,
            body:
                'Blocked mentions ${members.map((u) => '@${u.substring(2)}').join(' ')}',
            threadItemId: lobby['lobbyId']! as String,
          );
          expect(intents.mentioned.intersection(members.toSet()), isEmpty);
          final blockedCalls = await peerSetCalls();
          expect(
            {for (final user in members) user: blockedCalls[user] ?? 0},
            {for (final user in members) user: 0},
            reason:
                'blocked recipients must be rejected before discoverability',
          );

          // A stranger still pays for discovery and gets no access without
          // mutual visibility. This guards against bypassing the wall for all.
          await sql('TRUNCATE public.test_peer_set_calls');
          final strangerAccess = await writer.execute(
            "SELECT access FROM public.questions_access_levels('$beaconId', "
            "ARRAY['$stranger'])",
          );
          expect(strangerAccess.single.single, 0);
          await expectParity([stranger]);
          expect((await peerSetCalls())[stranger], greaterThan(0));

          // Role 6 alone does not grant wall readability. Reciprocal trust
          // supplies discoverability; the peer-set lookup must remain.
          final discoveryAddressee = recipients[10];
          final hierarchyReader = recipients[11];
          await sql(
            'INSERT INTO public.beacon_participant '
            '(beacon_id, user_id, role, status, room_access) '
            "VALUES ('$beaconId', '$discoveryAddressee', 6, 0, 0)",
          );
          await sql('TRUNCATE public.test_peer_set_calls');
          final untrustedAddressee = await writer.execute(
            "SELECT access FROM public.questions_access_levels('$beaconId', "
            "ARRAY['$discoveryAddressee'])",
          );
          expect(
            untrustedAddressee.single.single,
            0,
            reason: 'role 6 alone cannot bypass the content wall',
          );
          expect(
            (await peerSetCalls())[discoveryAddressee] ?? 0,
            greaterThan(0),
          );
          for (final user in [discoveryAddressee, hierarchyReader]) {
            await sql(
              'INSERT INTO public.vote_user (subject, object, amount) VALUES '
              "('$user', '$author', 1), ('$author', '$user', 1)",
            );
          }
          // Owning a child Request supplies hierarchy reading but no own or
          // addressed Questions standing on its parent. Discovery adds write.
          await sql(
            'INSERT INTO public.beacon '
            '(id, user_id, title, description, status, kind, '
            'is_discoverable, published_at, parent_beacon_id) '
            "VALUES ('Bqcostchild', '$hierarchyReader', 'Child', '', 0, 0, "
            "false, now(), '$beaconId')",
          );
          await sql('TRUNCATE public.test_peer_set_calls');
          final discoveryLevels = await writer.execute(
            Sql.named(
              'SELECT user_id, access FROM public.questions_access_levels( '
              '@beacon, @users::text[])',
            ),
            parameters: {
              'beacon': beaconId,
              'users': [discoveryAddressee, hierarchyReader],
            },
          );
          expect(
            {for (final row in discoveryLevels) row[0]: row[1]},
            {
              discoveryAddressee: 2,
              hierarchyReader: 2,
            },
          );
          await expectParity([discoveryAddressee, hierarchyReader]);
          expect(
            {for (final user in members) user: calls[user] ?? 0},
            {for (final user in members) user: 0},
            reason: 'cheap standing must avoid the discoverability peer set',
          );
        });
      }
    });

    test('unread Questions policy cost is independent of message count', () async {
      final lobby = await rooms.beaconLobby(beaconId: beaconId, userId: author);
      final lobbyId = lobby['lobbyId']! as String;
      final viewer = recipients.first;
      final repo = BeaconRoomRepository(db);
      await sql(
        'CREATE TABLE public.test_questions_policy_calls (beacon_id text)',
      );
      await sql(
        'ALTER FUNCTION public.questions_access_levels(text, text[]) '
        'RENAME TO test_original_questions_access_levels',
      );
      await sql(r'''
CREATE FUNCTION public.questions_access_levels(p_beacon_id text, p_user_ids text[])
RETURNS TABLE(user_id text, access smallint) LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.test_questions_policy_calls VALUES (p_beacon_id);
  RETURN QUERY SELECT * FROM public.test_original_questions_access_levels(
    p_beacon_id, p_user_ids);
END;
$$
''');
      try {
        Future<void> insertQuestions(int count) => writer.execute(
          Sql.named('''
INSERT INTO public.beacon_room_message
  (beacon_id, author_id, body, thread_item_id, created_at)
SELECT @beacon, @author, 'Question', @lobby,
       '2030-01-02'::timestamptz + n * interval '1 minute'
FROM generate_series(1, @count::integer) n
'''),
          parameters: {
            'beacon': beaconId,
            'author': author,
            'lobby': lobbyId,
            'count': count,
          },
        );
        Future<int> policyCalls() async =>
            (await writer.execute(
                  'SELECT count(*)::integer FROM public.test_questions_policy_calls '
                  "WHERE beacon_id = '$beaconId'",
                )).single.single!
                as int;
        Future<void> expectCounts(
          int questions,
          int discussion,
          String? oldest, {
          String? user,
        }) async {
          final viewing = user ?? viewer;
          final summary = (await repo.unreadRoomSummaries(
            [beaconId],
            viewerUserId: viewing,
          ))[beaconId]!;
          expect(summary.questions, questions);
          expect(summary.discussion, discussion);
          expect(summary.oldestRoom, oldest);
          final counts = await writer.execute(
            'SELECT ${requestDiscussionUnreadCountSql(viewer: "'$viewing'", beaconId: "'$beaconId'")}, '
            '${requestQuestionsUnreadCountSql(viewer: "'$viewing'", beaconId: "'$beaconId'")}',
          );
          expect(counts.single, [discussion, questions]);
        }

        await insertQuestions(1);
        await sql('TRUNCATE public.test_questions_policy_calls');
        final one = (await repo.unreadRoomSummaries(
          [beaconId],
          viewerUserId: viewer,
        ))[beaconId]!;
        final oneCalls = await policyCalls();
        expect(one.questions, 1);
        expect(one.oldestRoom, 'questions');
        expect(oneCalls, greaterThan(0), reason: 'counting hook must fire');
        await insertQuestions(9);
        await sql('TRUNCATE public.test_questions_policy_calls');
        final ten = (await repo.unreadRoomSummaries(
          [beaconId],
          viewerUserId: viewer,
        ))[beaconId]!;
        final tenCalls = await policyCalls();
        expect(ten.questions, 10);
        expect(ten.oldestRoom, 'questions');
        await expectCounts(10, 0, 'questions');
        // Discovery grants permission to read/ask, but a viewer joins the
        // notification/unread audience only after gaining standing or posting.
        // This viewer has neither; access 2 and zero unread are intentional.
        const outsideAudience = stranger;
        await sql(
          'INSERT INTO public.vote_user (subject, object, amount) VALUES '
          "('$outsideAudience', '$author', 1), ('$author', '$outsideAudience', 1)",
        );
        final readable = await writer.execute(
          "SELECT access FROM public.questions_access_levels('$beaconId', "
          "ARRAY['$outsideAudience'])",
        );
        expect(readable.single.single, 2);
        final audienceMembership = await writer.execute(
          "SELECT EXISTS (SELECT 1 FROM public.questions_audience('$beaconId') "
          "WHERE user_id = '$outsideAudience')",
        );
        expect(
          audienceMembership.single.single,
          isFalse,
          reason: 'permission to read does not enroll a discoverable spectator',
        );
        final hasPosted = await writer.execute(
          'SELECT EXISTS (SELECT 1 FROM public.beacon_room_message '
          "WHERE thread_item_id = '$lobbyId' AND author_id = '$outsideAudience')",
        );
        expect(hasPosted.single.single, isFalse);
        await expectCounts(0, 0, null, user: outsideAudience);
        // Admit the viewer to discussion and give it the older message.
        await sql(
          'INSERT INTO public.beacon_participant '
          '(beacon_id, user_id, role, status, room_access) '
          "VALUES ('$beaconId', '$viewer', 1, 0, 3)",
        );
        await sql(
          'INSERT INTO public.beacon_room_message '
          '(beacon_id, author_id, body, created_at) '
          "VALUES ('$beaconId', '$author', 'Discussion', '2030-01-01')",
        );
        await expectCounts(10, 1, 'discussion');
        expect(
          tenCalls,
          oneCalls,
          reason:
              'policy calls for one=$oneCalls and ten=$tenCalls unread questions',
        );
      } finally {
        await sql('DROP FUNCTION public.questions_access_levels(text, text[])');
        await sql(
          'ALTER FUNCTION public.test_original_questions_access_levels(text, text[]) '
          'RENAME TO questions_access_levels',
        );
        await sql('DROP TABLE public.test_questions_policy_calls');
      }
    });

    test('the counting hook sees the peer set the content wall computes for '
        'a stranger of the discoverable Request', () async {
      // Guards the cost test above against a hook that never fires: the
      // wall's discoverability clause needs the stranger's peer set.
      final wall = await writer.execute(
        "SELECT public.beacon_can_read_content('$beaconId', '$stranger')",
      );
      expect(wall.single.single, isFalse);
      expect((await peerSetCalls())[stranger], greaterThan(0));
    });
  }, skip: skipReason ?? false);
}

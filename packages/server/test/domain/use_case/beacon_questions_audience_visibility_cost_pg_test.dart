@Tags(['pg'])
library;

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
      db = TenturaDb(target.databaseEnv);
    });

    tearDownAll(() async {
      if (skipReason != null) return;
      await db.close();
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

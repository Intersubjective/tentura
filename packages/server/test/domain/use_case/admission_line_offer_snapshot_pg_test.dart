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
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_capability_event_repository.dart';
import 'package:tentura_server/data/repository/room_message_snapshot_lookup.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';
import 'package:tentura_server/domain/entity/room_message_snapshot.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';

// The «X was admitted to the discussion» line quotes what the helper wrote
// in their offer. The quote is a snapshot taken when the author admits them
// and stored in the line itself (system payload key `offerNote`): later edits
// or a withdrawal of the offer must not change or remove it.

const _beaconId = 'Badmquote01';
const _authorId = 'Uadmquoteau';
const _helperId = 'Uadmquotehe';
const _joinedMarker = 9;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ADMISSION_LINE_OFFER_SNAPSHOT_TEST_DB',
    defaultNamePrefix: 'tentura_test_adm_quote',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('admission line offer snapshot', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late _Harness harness;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      harness = _Harness.build(database, target.databaseEnv);
    });

    setUp(() async {
      if (skipReason != false) return;
      await _resetFixture(writer);
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<void> offerAndAdmit(String message) async {
      await harness.helpOfferCase.offerHelp(
        beaconId: _beaconId,
        userId: _helperId,
        message: message,
      );
      await harness.coordinationCase.acceptHelpOffer(
        beaconId: _beaconId,
        offerUserId: _helperId,
        actorUserId: _authorId,
      );
    }

    test(
      'admitting a helper who offered through Offer help stores their offer '
      'text in the admission line',
      () async {
        await offerAndAdmit('I have a van, free 10-12.');

        final payload = await _joinedLinePayload(writer);
        expect(payload['joinedUserId'], _helperId);
        expect(payload['offerNote'], 'I have a van, free 10-12.');
      },
      skip: skipReason,
    );

    test(
      'the admission line keeps the original quote after the helper edits '
      'their offer',
      () async {
        await offerAndAdmit('I have a van, free 10-12.');

        await harness.helpOfferCase.offerHelp(
          beaconId: _beaconId,
          userId: _helperId,
          message: 'Actually a bike',
        );

        final payload = await _joinedLinePayload(writer);
        expect(payload['offerNote'], 'I have a van, free 10-12.');
      },
      skip: skipReason,
    );

    test(
      'the admission line keeps the quote after the helper withdraws',
      () async {
        await offerAndAdmit('I have a van, free 10-12.');

        await harness.helpOfferCase.withdraw(
          beaconId: _beaconId,
          userId: _helperId,
          withdrawReason: 'timing',
          message: 'sorry',
        );

        final payload = await _joinedLinePayload(writer);
        expect(payload['offerNote'], 'I have a van, free 10-12.');
      },
      skip: skipReason,
    );

    test(
      'an offer written through the room offer path is quoted in the '
      'admission line too, and stays after a later edit',
      () async {
        final room = BeaconRoomRepository(database);
        await room.participantOfferHelp(
          beaconId: _beaconId,
          userId: _helperId,
          note: 'Room offer: tools',
        );
        await room.inviteOfferUserToBeaconRoom(
          beaconId: _beaconId,
          offerUserId: _helperId,
          authorUserId: _authorId,
        );

        final payload = await _joinedLinePayload(writer);
        expect(payload['offerNote'], 'Room offer: tools');

        await room.participantOfferHelp(
          beaconId: _beaconId,
          userId: _helperId,
          note: 'Room offer: changed',
        );
        final after = await _joinedLinePayload(writer);
        expect(after['offerNote'], 'Room offer: tools');
      },
      skip: skipReason,
    );

    // The open discussion learns of the admission line over the socket: the
    // line's insert hint must name both the author who admitted and the
    // helper who was admitted, so the line (with its quote) reaches both open
    // rooms without a reload.
    test(
      'the admission line’s realtime hint reaches the author and the '
      'admitted helper, and the line it announces carries the quote',
      () async {
        final listener = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );
        final hints = <Map<String, dynamic>>[];
        await listener.execute('LISTEN entity_changes');
        final sub = listener.channels['entity_changes'].listen(
          (payload) => hints.add(jsonDecode(payload) as Map<String, dynamic>),
        );
        addTearDown(() async {
          await sub.cancel();
          await listener.close();
        });

        await offerAndAdmit('I have a van, free 10-12.');

        final lineId = await _joinedLineId(writer);
        Set<String> recipients() => {
          for (final h in hints)
            if (h['entity'] == 'room_message' && h['message_id'] == lineId)
              ...(h['user_ids'] as List).cast<String>(),
        };
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (DateTime.now().isBefore(deadline) &&
            !recipients().containsAll({_authorId, _helperId})) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(recipients(), containsAll({_authorId, _helperId}));

        // The hint is either answered with a paint of the line (then the
        // painted payload must hold the quote) or left bare so the client
        // refetches the stored row (lookup returns null; the stored row,
        // asserted below, holds the quote). A paint without the quote, or a
        // lookup that fails, is wrong either way.
        final snapshot = await RoomMessageSnapshotLookup(
          database,
        ).findEligibleInsert(messageId: lineId, beaconId: _beaconId);
        expect(
          snapshot,
          anyOf(
            isNull,
            isA<RoomMessageSnapshot>().having(
              (s) => s.systemPayload?['offerNote'],
              'painted offerNote',
              'I have a van, free 10-12.',
            ),
          ),
        );
        final payload = await _joinedLinePayload(writer);
        expect(payload['offerNote'], 'I have a van, free 10-12.');
      },
      skip: skipReason,
    );
  }, skip: skipReason);
}

Future<String> _joinedLineId(Connection writer) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT id
FROM public.beacon_room_message
WHERE beacon_id = @b AND semantic_marker = @marker
ORDER BY created_at DESC
LIMIT 1
'''),
    parameters: {'b': _beaconId, 'marker': _joinedMarker},
  );
  expect(rows, hasLength(1), reason: 'one admission line');
  return rows.single[0]! as String;
}

Future<Map<String, Object?>> _joinedLinePayload(Connection writer) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT system_payload::text
FROM public.beacon_room_message
WHERE beacon_id = @b AND semantic_marker = @marker
ORDER BY created_at DESC
LIMIT 1
'''),
    parameters: {'b': _beaconId, 'marker': _joinedMarker},
  );
  expect(rows, hasLength(1), reason: 'one admission line');
  return (jsonDecode(rows.single[0]! as String) as Map).cast<String, Object?>();
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon_help_offer,
  public.inbox_item,
  public.beacon,
  public."user"
CASCADE
''');
  for (final (id, name) in [
    (_authorId, 'Ada Author'),
    (_helperId, 'Hal Helper'),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
      parameters: {'id': id, 'name': name, 'key': 'key-$id'},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (
  '$_beaconId', '$_authorId', 'Admission quote beacon', 'desc',
  ${BeaconStatus.open.smallintValue}
)
''');
}

final class _Harness {
  const _Harness({
    required this.helpOfferCase,
    required this.coordinationCase,
    required this.systemSettlement,
  });

  final HelpOfferCase helpOfferCase;
  final CoordinationCase coordinationCase;
  final AttentionSystemSettlementRepository systemSettlement;

  factory _Harness.build(TenturaDb db, Env env) {
    final logger = Logger('AdmissionLineOfferSnapshotPgTest');
    final unitOfWork = MutatingUnitOfWork(db);
    final dispatch = AttentionDispatchRepository(db, logger);
    final attention = TransactionalAttentionCase(unitOfWork, dispatch);
    final systemSettlement = AttentionSystemSettlementRepository(db);
    final room = BeaconRoomRepository(db);
    final helpOffers = HelpOfferRepository(db);
    final commitments = CommitmentRepository(db);
    final beacons = BeaconRepository(db);
    final access = BeaconAccessRepository(db);
    final hierarchy = BeaconHierarchyRepository(db);
    final attentionIntents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(
        room,
        db,
        helpOffers,
        commitments,
      ),
      UserRepository(
        env,
        db,
        _NoopInviteGenealogyRepository(),
        InviteSeedPromptRepositoryMock(),
      ),
      access,
      FakeUserBlockRepository(),
    );
    final commitmentQuery = CommitmentQueryCase(
      commitments,
      helpOffers,
      env: env,
      logger: logger,
    );
    return _Harness(
      helpOfferCase: HelpOfferCase(
        helpOffers,
        beacons,
        commitments,
        InboxRepository(db),
        CapabilityCase(
          PersonCapabilityEventRepository(db),
          env: env,
          logger: logger,
        ),
        FakeBeaconAccessGuard(),
        roomRepository: room,
        attentionIntents: attentionIntents,
        attention: attention,
        attentionSystemSettlement: systemSettlement,
        env: env,
        logger: logger,
      ),
      coordinationCase: CoordinationCase(
        beacons,
        helpOffers,
        CoordinationRepository(
          db,
          DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
          VoteUserFriendshipLookup(db),
          room,
        ),
        room,
        FakeUserBlockRepository(),
        commitments,
        commitmentQuery,
        hierarchy,
        attentionIntents: attentionIntents,
        attention: attention,
        attentionSystemSettlement: systemSettlement,
        guard: FakeBeaconAccessGuard(),
        env: env,
        logger: logger,
      ),
      systemSettlement: systemSettlement,
    );
  }
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/room_baton_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/room_baton.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/room_baton_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/mocks/invite_seed_prompt_repository_mock.dart';

// The case creates and answers a real baton; account erasure exercises the
// partner foreign key rather than manufacturing a candidate state.
const _author = 'Ubatonerase_au1';
const _candA = 'Ubatonerase_ca1';
const _candB = 'Ubatonerase_cb1';
const _partnerX = 'Ubatonerase_px1';
const _request = 'Bbatonerase_rq1';
const _ask = 'Who can bring the ladder?';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_BATON_ERASED_PARTNER_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_baton_erased_partner',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  group('Collecting baton after an accepted partner account is erased', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late RoomBatonCase batonCase;
    late RoomBatonRepository batons;
    late BeaconRoomRepository room;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      batonCase = _buildCase(database, target.databaseEnv);
      batons = RoomBatonRepository(database);
      room = BeaconRoomRepository(database);
    });
    setUp(() => _resetFixture(writer));
    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<RoomBaton> create() => batonCase.create(
      actorId: _author,
      beaconId: _request,
      text: _ask,
      candidates: [(userId: _candA, tier: 1), (userId: _candB, tier: 1)],
    );

    Future<void> answer(RoomBaton baton, String user, {bool canHelp = true}) =>
        batonCase.respond(actorId: user, batonId: baton.id, canHelp: canHelp);

    Future<void> acceptPair(RoomBaton baton) async {
      await batonCase.respond(
        actorId: _candA,
        batonId: baton.id,
        canHelp: true,
        partnerUserId: _partnerX,
      );
      await batonCase.partnerRespond(
        actorId: _partnerX,
        batonId: baton.id,
        inviterUserId: _candA,
        accept: true,
      );
    }

    Future<void> erasePartner(RoomBaton baton) async {
      await writer.execute(
        Sql.named('DELETE FROM public.beacon_participant WHERE user_id = @id'),
        parameters: {'id': _partnerX},
      );
      await writer.execute(
        Sql.named('DELETE FROM public."user" WHERE id = @id'),
        parameters: {'id': _partnerX},
      );
      final rows = await writer.execute(
        Sql.named('''
SELECT response, partner_response, partner_user_id
FROM public.beacon_room_baton_candidate
WHERE baton_id = @baton AND user_id = @user'''),
        parameters: {'baton': baton.id, 'user': _candA},
      );
      expect(
        rows.single.toList(),
        [1, 1, null],
        reason: 'erasure must leave the accepted answer and clear only the FK',
      );
    }

    Future<int> allAnsweredOccurrences() async {
      final rows = await writer.execute(
        Sql.named('''
SELECT count(*) FROM public.attention_occurrence AS occ
JOIN public.attention_occurrence_recipient AS recipient
  ON recipient.occurrence_id = occ.id
WHERE occ.event_type = 'batonAllAnswered' AND recipient.account_id = @author
'''),
        parameters: {
          'author': _author,
        },
      );
      return rows.single[0]! as int;
    }

    Future<void> expectCollecting(RoomBaton baton) async {
      final stored = (await batons.getById(baton.id))!;
      expect(stored.status, BatonStatus.collecting);
      expect(stored.takerId, isNull);
      expect(stored.coTakerId, isNull);
      final markers = await writer.execute(
        Sql.named('''
SELECT id FROM public.beacon_room_message
WHERE beacon_id = @beacon AND semantic_marker = @marker
  AND system_payload ->> 'batonId' = @baton'''),
        parameters: {
          'beacon': _request,
          'marker': BeaconRoomSemanticMarker.batonTaken,
          'baton': baton.id,
        },
      );
      expect(markers, isEmpty);
    }

    Future<void> expectIntactPairPickable({String? userId}) async {
      final intact = await create();
      await acceptPair(intact);
      // B is still waiting, so the accepted pair is the only eligible entry.
      await batonCase.select(
        actorId: _author,
        batonId: intact.id,
        userId: userId,
      );
      final stored = (await batons.getById(intact.id))!;
      expect(stored.status, BatonStatus.taken);
      expect(stored.takerId, _candA);
      expect(stored.coTakerId, _partnerX);
    }

    test(
      'accepted pair becomes unanswered in both repository and author card',
      () async {
        final baton = await create();
        await answer(baton, _candB);
        await acceptPair(baton);
        expect(
          await batons.hasUnansweredCandidate(baton.id),
          isFalse,
          reason: 'B answered and A still has an intact accepted partner',
        );

        await erasePartner(baton);

        final messages = await room.listMessagesEnriched(
          beaconId: _request,
          viewerUserId: _author,
        );
        final message = messages.singleWhere((m) => m['id'] == baton.messageId);
        final projection =
            jsonDecode(message['batonDataJson']! as String) as Map;
        final a = (projection['candidates'] as List)
            .cast<Map<String, Object?>>()
            .singleWhere(
              (c) => c['userId'] == _candA,
            );
        expect(a['response'], 'waiting');
        expect(projection['allAnswered'], isFalse);
        expect(await batons.hasUnansweredCandidate(baton.id), isTrue);
      },
    );

    test(
      'next answer clears the completed round without another author notice',
      () async {
        final baton = await create();
        await answer(baton, _candB);
        await acceptPair(baton);
        expect(await batons.hasUnansweredCandidate(baton.id), isFalse);
        expect(await allAnsweredOccurrences(), 1);
        expect(
          (await batons.getById(baton.id))!.allAnsweredNotifiedAt,
          isNotNull,
        );
        await erasePartner(baton);

        await answer(baton, _candB);

        expect(await allAnsweredOccurrences(), 1);
        expect(await batons.hasUnansweredCandidate(baton.id), isTrue);
        expect((await batons.getById(baton.id))!.allAnsweredNotifiedAt, isNull);
      },
    );

    test(
      'last solo answer cannot complete a round with an erased partner',
      () async {
        final baton = await create();
        await acceptPair(baton);
        await erasePartner(baton);

        await answer(baton, _candB);

        expect(await allAnsweredOccurrences(), 0);
        expect((await batons.getById(baton.id))!.allAnsweredNotifiedAt, isNull);
      },
    );

    test(
      'answering again alone completes the round only after the waiting ends',
      () async {
        final baton = await create();
        await acceptPair(baton);
        await erasePartner(baton);
        await answer(baton, _candB);
        final noticesWhileWaiting = await allAnsweredOccurrences();
        final stampWhileWaiting = (await batons.getById(
          baton.id,
        ))!.allAnsweredNotifiedAt;
        final unansweredBefore = await batons.hasUnansweredCandidate(baton.id);

        await answer(baton, _candA);

        final a = (await batons.getCandidates(baton.id)).singleWhere(
          (candidate) => candidate.userId == _candA,
        );
        expect(a.response, BatonResponse.canHelp);
        expect(a.partnerUserId, isNull);
        expect(a.partnerResponse, isNull);
        expect(await allAnsweredOccurrences(), 1);
        expect(
          (await batons.getById(baton.id))!.allAnsweredNotifiedAt,
          isNotNull,
        );
        expect(await batons.hasUnansweredCandidate(baton.id), isFalse);
        expect(noticesWhileWaiting, 0);
        expect(stampWhileWaiting, isNull);
        expect(unansweredBefore, isTrue);
      },
    );

    test(
      'manual picks refuse both members while the erased pair waits',
      () async {
        await expectIntactPairPickable(userId: _candA);
        await expectIntactPairPickable(userId: _partnerX);
        final baton = await create();
        await acceptPair(baton);
        await answer(baton, _candB);
        await erasePartner(baton);

        for (final user in [_partnerX, _candA]) {
          await expectLater(
            batonCase.select(actorId: _author, batonId: baton.id, userId: user),
            throwsA(isA<BatonTakerNotAvailableException>()),
          );
          await expectCollecting(baton);
        }
        expect(await batons.hasUnansweredCandidate(baton.id), isTrue);
      },
    );

    test(
      'automatic pick skips the waiting pair for an answered peer in its tier',
      () async {
        await expectIntactPairPickable();
        final baton = await create();
        await acceptPair(baton);
        await answer(baton, _candB);
        await erasePartner(baton);
        final waitingBeforePick = await batons.hasUnansweredCandidate(baton.id);

        await batonCase.select(actorId: _author, batonId: baton.id);

        final stored = (await batons.getById(baton.id))!;
        expect(stored.status, BatonStatus.taken);
        expect(stored.takerId, _candB);
        expect(stored.coTakerId, isNull);
        expect(waitingBeforePick, isTrue);
      },
    );

    test(
      'automatic pick leaves collection open when the only yes lost a partner',
      () async {
        await expectIntactPairPickable();
        final baton = await create();
        await acceptPair(baton);
        await answer(baton, _candB);
        await erasePartner(baton);
        await answer(baton, _candB, canHelp: false);

        await expectLater(
          batonCase.select(actorId: _author, batonId: baton.id),
          throwsA(isA<BatonTakerNotAvailableException>()),
        );
        await expectCollecting(baton);
        expect(await batons.hasUnansweredCandidate(baton.id), isTrue);
      },
    );
  });
}

RoomBatonCase _buildCase(TenturaDb db, Env env) {
  final logger = Logger('RoomBatonErasedPartnerPgTest');
  final blocks = UserBlockRepository(env, db);
  final room = BeaconRoomRepository(db);
  final attention = TransactionalAttentionCase(
    MutatingUnitOfWork(db),
    AttentionDispatchRepository(db, logger),
  );
  final attentionIntents = AttentionIntentCase(
    BeaconRoomNotificationContextRepository(
      room,
      db,
      HelpOfferRepository(db),
      CommitmentRepository(db),
    ),
    UserRepository(
      env,
      db,
      _NoopInviteGenealogyRepository(),
      InviteSeedPromptRepositoryMock(),
    ),
    BeaconAccessRepository(db),
    blocks,
  );
  return RoomBatonCase(
    RoomBatonRepository(db),
    room,
    BeaconHierarchyRepository(db),
    PostLockRepository(db),
    attention,
    attentionIntents,
    env: env,
    logger: logger,
  );
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon_room_baton_candidate,
  public.beacon_room_baton,
  public.beacon_room_message,
  public.user_block,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  final users = [
    _author,
    _candA,
    _candB,
    _partnerX,
  ];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {
        'id': users[i],
        'key': pgTestPublicKey('batonerase', i + 1),
      },
    );
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now())
''');
  var n = 0;
  for (final user in users) {
    await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pbatonerasesel${(n++).toString().padLeft(3, '0')}', '$_request', '$user', 0, 0, 3)
''');
  }
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

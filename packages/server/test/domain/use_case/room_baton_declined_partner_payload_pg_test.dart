@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

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

const _author = 'Ubatondec_au1';
const _candA = 'Ubatondec_ca1';
const _candB = 'Ubatondec_cb1';
const _partnerX = 'Ubatondec_px1';
const _request = 'Bbatondec_rq1';

const _titles = <String, String>{
  _author: 'Author Name',
  _candA: 'Alice Name',
  _candB: 'Bob Name',
  _partnerX: 'Xenia Name',
};

// A candidate names a partner and the partner declines, both through
// RoomBatonCase (the state production writes). The room payload each person
// reads afterwards: the inviter learns who can't join, nobody else is told.

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_BATON_DECLINED_PARTNER_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_baton_declined_partner',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  group('payload after a partner declined the invitation', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late RoomBatonCase batonCase;
    late BeaconRoomRepository room;
    late RoomBaton baton;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      batonCase = _buildCase(database, target.databaseEnv);
      room = BeaconRoomRepository(database);
    });

    setUp(() async {
      await _resetFixture(writer);
      baton = await batonCase.create(
        actorId: _author,
        beaconId: _request,
        text: 'Who can bring the ladder?',
        candidates: [(userId: _candA, tier: 1), (userId: _candB, tier: 2)],
      );
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
        accept: false,
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<Map<String, Object?>> payloadFor(String viewer) async {
      final rows = await room.listMessagesEnriched(
        beaconId: _request,
        viewerUserId: viewer,
      );
      final raw = rows.singleWhere(
        (r) => r['id'] == baton.messageId,
      )['batonDataJson'];
      expect(raw, isNotNull, reason: 'viewer $viewer must get baton data');
      return (jsonDecode(raw! as String) as Map).cast<String, Object?>();
    }

    test('the inviter sees who can not join, with name', () async {
      final p = await payloadFor(_candA);

      expect(p['viewerRole'], 'candidate');
      expect(p['myResponse'], 'waiting');
      expect(p['myPartner'], {
        'id': _partnerX,
        'title': _titles[_partnerX],
        'status': 'declined',
      });
    });

    test('the declined partner is not asked again', () async {
      final p = await payloadFor(_partnerX);

      expect(p['status'], 'collecting');
      final invites = p['partnerInvites'];
      if (p['viewerRole'] == 'partner') {
        expect(invites, isA<List<Object?>>());
      }
      expect(
        ((invites as List<Object?>?) ?? const <Object?>[])
            .cast<Map<String, Object?>>()
            .where(
              (i) => i['fromUserId'] == _candA && i['status'] == 'pending',
            ),
        isEmpty,
      );
    });

    test('the author sees the inviter waiting, without a partner', () async {
      await batonCase.respond(
        actorId: _candB,
        batonId: baton.id,
        canHelp: true,
      );
      final p = await payloadFor(_author);

      final a = (p['candidates']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere((c) => c['userId'] == _candA);
      expect(a['response'], 'waiting');
      expect(a.containsKey('partner'), isFalse);
      expect((p['pairs'] as List?) ?? const [], isEmpty);
      expect(p['eligibleCount'], 1, reason: 'only B, never A');
      final raw = jsonEncode(p);
      expect(raw, isNot(contains(_partnerX)));
      expect(raw, isNot(contains(_titles[_partnerX])));
    });

    test('a second answer by the declined partner is rejected', () async {
      for (final accept in [true, false]) {
        await expectLater(
          batonCase.partnerRespond(
            actorId: _partnerX,
            batonId: baton.id,
            inviterUserId: _candA,
            accept: accept,
          ),
          throwsA(isA<BatonNotPartnerException>()),
        );
      }
    });
  });
}

RoomBatonCase _buildCase(TenturaDb db, Env env) {
  final logger = Logger('RoomBatonDeclinedPartnerPgTest');
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
VALUES (@id, @title, @key)
'''),
      parameters: {
        'id': users[i],
        'title': _titles[users[i]] ?? users[i],
        'key': pgTestPublicKey('batondec', i + 1),
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
VALUES ('Pbatondec${(n++).toString().padLeft(3, '0')}', '$_request', '$user', 0, 0, 3)
''');
  }
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

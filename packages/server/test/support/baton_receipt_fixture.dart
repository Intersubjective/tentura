import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/attention_channel_delivery_repository.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';
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
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/room_baton.dart';
import 'package:tentura_server/domain/port/beacon_notification_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_channel_delivery_case.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/room_baton_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import 'disposable_pg_target.dart';
import 'pg_test_public_keys.dart';
import 'mocks/invite_seed_prompt_repository_mock.dart';

const batonAnna = 'Ubaton0000001';
// Carol sorts first by ID. Boris still answers first in propose().
const batonBoris = 'Ubaton0000003';
const batonCarol = 'Ubaton0000002';
const batonJoinedRequest = 'BbatonJoined1';
const batonPairWithExcerptRequest = 'BbatonPairAsk';
const batonDeclinedRequest = 'BbatonDecline';
const batonPairWithoutExcerptRequest = 'BbatonNoQuote';
const batonSoloWithoutExcerptRequest = 'BbatonSolo001';

final class BatonReceiptFixture {
  BatonReceiptFixture(this.target);

  final DisposablePgTarget target;
  late final DisposablePgWriterSession session;
  late final TenturaDb db;
  late final RoomBatonCase batonCase;
  late final BeaconRoomRepository room;

  late final query = QueryAttention(query: AttentionRepository(db));
  late final schema = TenturaGraphQL(
    GraphQLSchema(
      queryType: GraphQLObjectType('query_root', 'Attention test queries')
        ..fields.addAll([
          query.attentionFeed,
          query.attentionRequestHistory,
        ]),
    ),
    customTypes: customTypes,
  );

  Future<void> open({bool activityStream = false}) async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: activityStream,
    );
    db = openDisposablePgDatabase(target);
    final env = target.databaseEnv;
    final logger = Logger('BatonReceiptFixture');
    room = BeaconRoomRepository(db);
    final blocks = UserBlockRepository(env, db);
    batonCase = RoomBatonCase(
      RoomBatonRepository(db),
      room,
      BeaconHierarchyRepository(db),
      PostLockRepository(db),
      TransactionalAttentionCase(
        MutatingUnitOfWork(db),
        AttentionDispatchRepository(db, logger),
      ),
      AttentionIntentCase(
        BeaconRoomNotificationContextRepository(
          room,
          db,
          HelpOfferRepository(db),
          CommitmentRepository(db),
        ),
        UserRepository(
          env,
          db,
          _UnusedGenealogy(),
          InviteSeedPromptRepositoryMock(),
        ),
        BeaconAccessRepository(db),
        blocks,
      ),
      env: env,
      logger: logger,
    );
    for (final (index, (id, name)) in [
      (batonAnna, 'Anna'),
      (batonBoris, 'Boris'),
      (batonCarol, 'Carol'),
    ].indexed) {
      await session.writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) '
          'VALUES (@id, @name, @key)',
        ),
        parameters: {
          'id': id,
          'name': name,
          'key': pgTestPublicKey('batonreceipt', index + 1),
        },
      );
    }
  }

  Future<void> close() =>
      tearDownDisposablePgWriter(session: session, drift: db);

  Future<RoomBaton> propose(
    String request, {
    bool pair = true,
    bool withExcerpt = true,
  }) async {
    await session.writer.execute(
      Sql.named(
        'INSERT INTO public.beacon (id, user_id, title, description, status, published_at) '
        "VALUES (@id, @author, 'Moving day', '', 0, now())",
      ),
      parameters: {'id': request, 'author': batonAnna},
    );
    for (final (index, user) in [batonBoris, batonCarol].indexed) {
      await session.writer.execute(
        Sql.named(
          'INSERT INTO public.beacon_participant '
          '(id, beacon_id, user_id, role, status, room_access) '
          'VALUES (@id, @request, @user, @role, 0, @access)',
        ),
        parameters: {
          'id': 'P${request.substring(1)}$index',
          'request': request,
          'user': user,
          'role': BeaconParticipantRoleBits.helper,
          'access': RoomAccessBits.admitted,
        },
      );
    }
    // A file-only message gives the ask a valid reply target with no text
    // available for a receipt excerpt, even if the reply is consulted.
    String? replyToMessageId;
    if (!withExcerpt) {
      final message = await room.insertRoomMessage(
        beaconId: request,
        authorId: batonAnna,
        body: '',
      );
      replyToMessageId = message.id;
      await room.insertRoomMessageAttachmentFile(
        attachmentId: 'A${request.substring(1)}',
        messageId: message.id,
        position: 0,
        storagePath: 'room-fixtures/$request.pdf',
        mime: 'application/pdf',
        sizeBytes: 128,
        displayName: 'Moving plan.pdf',
        mutatingUserId: batonAnna,
      );
    }
    final baton = await batonCase.create(
      actorId: batonAnna,
      beaconId: request,
      text: withExcerpt ? 'Bring chairs' : '',
      replyToMessageId: replyToMessageId,
      candidates: [
        (userId: batonBoris, tier: 1),
        if (pair) (userId: batonCarol, tier: 1),
      ],
    );
    await batonCase.respond(
      actorId: batonBoris,
      batonId: baton.id,
      canHelp: true,
      partnerUserId: pair ? batonCarol : null,
    );
    return baton;
  }

  Future<void> answer(RoomBaton baton, {required bool accept}) =>
      batonCase.partnerRespond(
        actorId: batonCarol,
        batonId: baton.id,
        inviterUserId: batonBoris,
        accept: accept,
      );

  Future<void> pick(RoomBaton baton, {String userId = batonBoris}) =>
      batonCase.select(
        actorId: batonAnna,
        batonId: baton.id,
        userId: userId,
      );

  // Drain the real worker with a logical clock. Multiple jobs for one account
  // are throttled, so advance past each lease without sleeping.
  Future<void> drainChannels() async {
    final worker = AttentionChannelDeliveryCase(
      AttentionChannelDeliveryRepository(db),
      const _NoExternalChannels(),
    );
    var now = DateTime.timestamp();
    for (var pass = 0; pass < 20; pass++) {
      final outstanding = await session.writer.execute(
        'SELECT count(*) FROM public.attention_channel_delivery '
        "WHERE status <> 'delivered'",
      );
      if (outstanding.single.single == 0) return;
      now = now.add(const Duration(minutes: 3));
      await worker.runDue(workerId: 'baton-receipt-test', now: now);
    }
    throw StateError('The baton notification worker did not drain');
  }
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _NoExternalChannels implements BeaconNotificationPort {
  const _NoExternalChannels();

  @override
  Future<void> handOffChannels(
    List<AttentionChannelDecision> decisions,
  ) async {}
}

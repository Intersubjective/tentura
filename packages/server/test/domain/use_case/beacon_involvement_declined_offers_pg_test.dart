@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/controllers/graphql/mappers/gql_v2_dto_maps.dart';
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
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_admission_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_capability_event_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_involvement_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/pg_test_public_keys.dart';

const _beaconId = 'Binvdecl0001';
const _authorId = 'Uinvdeclauth';
const _offererId = 'Uinvdecloffr';

List<String> _ids(Map<String, dynamic> gql, String key) =>
    List<String>.from(gql[key] as List? ?? const []);

/// Issue #770: `beaconInvolvement` must list author-declined offerers in
/// `declinedOfferIds` and keep self-withdrawals in `withdrawnIds` only.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_INVOLVEMENT_DECLINED_TEST_DB',
    defaultNamePrefix: 'tentura_test_inv_declined',
  );
  final skip = await pgSkipReason(target);

  group('BeaconInvolvement author decline vs self-withdrawal', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late _Harness harness;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      harness = _Harness.build(database, target.databaseEnv);
    });

    setUp(() async => _seed(writer));

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<Map<String, dynamic>> involvementForAuthor() async {
      final dto = await harness.involvement.asMap(
        beaconId: _beaconId,
        currentUserId: _authorId,
      );
      return beaconInvolvementResultToGqlMap(dto);
    }

    test(
      'author decline puts the offerer in declinedOfferIds not withdrawnIds',
      () async {
        await harness.helpOffers.offerHelp(
          beaconId: _beaconId,
          userId: _offererId,
        );
        await harness.coordination.declineHelpOffer(
          beaconId: _beaconId,
          offerUserId: _offererId,
          actorUserId: _authorId,
          reason: 'Not a fit right now',
        );

        final gql = await involvementForAuthor();

        expect(_ids(gql, 'declinedOfferIds'), contains(_offererId));
        expect(_ids(gql, 'withdrawnIds'), isNot(contains(_offererId)));
      },
      skip: skip,
    );

    test(
      'offerer self-withdrawal lists them in withdrawnIds only',
      () async {
        await harness.helpOffers.offerHelp(
          beaconId: _beaconId,
          userId: _offererId,
        );
        await harness.helpOffers.withdraw(
          beaconId: _beaconId,
          userId: _offererId,
          withdrawReason: 'timing',
        );

        final gql = await involvementForAuthor();

        expect(_ids(gql, 'withdrawnIds'), contains(_offererId));
        expect(_ids(gql, 'declinedOfferIds'), isNot(contains(_offererId)));
      },
      skip: skip,
    );

    test(
      're-offer after author decline lists the offerer in helpOfferedIds only',
      () async {
        await harness.helpOffers.offerHelp(
          beaconId: _beaconId,
          userId: _offererId,
        );
        await harness.coordination.declineHelpOffer(
          beaconId: _beaconId,
          offerUserId: _offererId,
          actorUserId: _authorId,
          reason: 'Maybe later',
        );

        final afterDecline = await involvementForAuthor();
        expect(_ids(afterDecline, 'declinedOfferIds'), contains(_offererId));
        expect(_ids(afterDecline, 'withdrawnIds'), isNot(contains(_offererId)));

        await harness.helpOffers.offerHelp(
          beaconId: _beaconId,
          userId: _offererId,
          message: 'Still available',
        );

        final gql = await involvementForAuthor();

        expect(_ids(gql, 'helpOfferedIds'), contains(_offererId));
        expect(_ids(gql, 'declinedOfferIds'), isNot(contains(_offererId)));
        expect(_ids(gql, 'withdrawnIds'), isNot(contains(_offererId)));
      },
      skip: skip,
    );
  });
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.beacon_help_offer_admission_event,
  public.beacon_help_offer_coordination,
  public.beacon_help_offer,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  for (final (i, id) in [_authorId, _offererId].indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': pgTestPublicKey('invdecl', i + 1)},
    );
  }
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@beacon, @author, 'Need a hand', 'desc', @status)
'''),
    parameters: {
      'beacon': _beaconId,
      'author': _authorId,
      'status': BeaconStatus.open.smallintValue,
    },
  );
}

final class _Harness {
  const _Harness({
    required this.helpOffers,
    required this.coordination,
    required this.involvement,
  });

  final HelpOfferCase helpOffers;
  final CoordinationCase coordination;
  final BeaconInvolvementCase involvement;

  factory _Harness.build(TenturaDb db, Env env) {
    final logger = Logger('BeaconInvolvementDeclinedOffersPgTest');
    final uow = MutatingUnitOfWork(db);
    final dispatch = AttentionDispatchRepository(db, logger);
    final attention = TransactionalAttentionCase(uow, dispatch);
    final systemSettlement = AttentionSystemSettlementRepository(db);
    final room = BeaconRoomRepository(db);
    final help = HelpOfferRepository(db);
    final commitments = CommitmentRepository(db);
    final beacons = BeaconRepository(db);
    final access = BeaconAccessRepository(db);
    final hierarchy = BeaconHierarchyRepository(db);
    final attentionIntents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(room, db, help, commitments),
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
      help,
      env: env,
      logger: logger,
    );
    return _Harness(
      helpOffers: HelpOfferCase(
        help,
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
      coordination: CoordinationCase(
        beacons,
        help,
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
      involvement: BeaconInvolvementCase(
        ForwardEdgeRepository(db),
        help,
        HelpOfferAdmissionRepository(db),
        InboxRepository(db),
        FakeBeaconAccessGuard(),
        env: env,
        logger: logger,
      ),
    );
  }
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

@Tags(['pg'])
library;

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mappers/gql_v2_dto_maps.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_help_offerer_forward_path.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/closure_repository.dart';
import 'package:tentura_server/data/repository/closure_receipts_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_capability_event_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/data/repository/trust_publish_repository.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_help_offerer_forward_path_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/trust_publisher_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';

/// `beaconHelpOffererForwardPath` answers "how did this Request reach the
/// helper?" with an ordered `path` next to the existing `edges`:
/// author → forwarder… → helper, built from the helper's arrival edge (the
/// latest forward to the helper that was live when they offered) and its
/// `parent_edge_id` chain. The wire shape asserted here (the map the
/// GraphQL resolver returns) is:
///
///     path: [{userId: String?, displayName: String?, anonymousCount: Int}]
///
/// A named node carries `userId` + `displayName` and `anonymousCount: 0`.
/// People hidden from the viewer by a block (either direction) become an
/// anonymous node (`userId`/`displayName` null); consecutive anonymous
/// people collapse into one node whose `anonymousCount` is how many it
/// stands for.
const _authorId = 'Uhpathauthor';
const _f1Id = 'Uhpathfwd001';
const _f2Id = 'Uhpathfwd002';
const _f3Id = 'Uhpathfwd003';
const _helperId = 'Uhpathhelper';
const _siblingId = 'Uhpathsiblng';
const _offPathId = 'Uhpathoffpth';
const _strangerId = 'Uhpathstrngr';
const _beaconId = 'Bhpathbeacon1';

const _names = {
  _authorId: 'Ann Author',
  _f1Id: 'Fred First',
  _f2Id: 'Fay Second',
  _f3Id: 'Finn Third',
  _helperId: 'Hal Helper',
  _siblingId: 'Sid Sibling',
  _offPathId: 'Olga Offpath',
  _strangerId: 'Stan Stranger',
};

/// Tables a path read must never write: the viewer's visible set and
/// mutual-visibility caches, Field first-seen and anchors, and every trust
/// store (evidence, materialised edges, votes, contacts, publish queue).
const _noWriteTables = [
  'person_visible_set_cache',
  'person_mutual_visibility_cache',
  'person_field_first_seen',
  'constellation_anchor',
  'user_trust_edge',
  'trust_evidence',
  'trust_publish_queue',
  'vote_user',
  'user_contact',
];

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HELP_PATH_ORDERED_CHAIN_TEST_DB',
    defaultNamePrefix: 'tentura_test_help_path_chain',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('help path of an accepted offer', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late _Harness harness;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(target: target);
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

    /// A → F1 → F2 → H is the live route. A → S → H is a sibling branch
    /// whose last hop was cancelled before H offered (it is newer than
    /// F2 → H, so ignoring the cancellation would pick it). F1 → X gives an
    /// involved person who is not on H's route.
    Future<void> seedThreeHopChain() async {
      await _forward(writer, 'Fhpath000001', _authorId, _f1Id, ago: '5 hours');
      await _forward(
        writer,
        'Fhpath000002',
        _f1Id,
        _f2Id,
        parent: 'Fhpath000001',
        ago: '4 hours',
      );
      await _forward(
        writer,
        'Fhpath000003',
        _f2Id,
        _helperId,
        parent: 'Fhpath000002',
        ago: '3 hours',
      );
      await _forward(
        writer,
        'Fhpath000004',
        _authorId,
        _siblingId,
        ago: '2 hours',
      );
      await _forward(
        writer,
        'Fhpath000005',
        _siblingId,
        _helperId,
        parent: 'Fhpath000004',
        ago: '90 minutes',
        cancelledAgo: '1 hour',
      );
      await _forward(
        writer,
        'Fhpath000006',
        _f1Id,
        _offPathId,
        parent: 'Fhpath000001',
        ago: '4 hours 30 minutes',
      );
    }

    /// A → F1 → F2 → F3 → H.
    Future<void> seedFourHopChain() async {
      await _forward(writer, 'Fhpath000011', _authorId, _f1Id, ago: '5 hours');
      await _forward(
        writer,
        'Fhpath000012',
        _f1Id,
        _f2Id,
        parent: 'Fhpath000011',
        ago: '4 hours',
      );
      await _forward(
        writer,
        'Fhpath000013',
        _f2Id,
        _f3Id,
        parent: 'Fhpath000012',
        ago: '3 hours',
      );
      await _forward(
        writer,
        'Fhpath000014',
        _f3Id,
        _helperId,
        parent: 'Fhpath000013',
        ago: '2 hours',
      );
    }

    Future<void> offerAndAccept() async {
      await harness.helpOfferCase.offerHelp(
        beaconId: _beaconId,
        userId: _helperId,
      );
      await harness.coordinationCase.acceptHelpOffer(
        beaconId: _beaconId,
        offerUserId: _helperId,
        actorUserId: _authorId,
      );
    }

    /// The map the GraphQL resolver hands to the client.
    Future<Map<String, dynamic>> helpPath(String viewerId) async =>
        forwardGraphResultToGqlMap(
          await harness.pathCase.asMap(
            beaconId: _beaconId,
            helpOffererId: _helperId,
            currentUserId: viewerId,
          ),
        );

    List<Map<String, dynamic>> pathOf(Map<String, dynamic> result) {
      final path = result['path'];
      expect(
        path,
        isA<List<dynamic>>(),
        reason: 'the result carries the ordered help path as `path`',
      );
      return (path as List<dynamic>).cast<Map<String, dynamic>>();
    }

    List<String?> idsOf(Map<String, dynamic> result) => [
      for (final node in pathOf(result)) node['userId'] as String?,
    ];

    Matcher namedNode(String userId) => allOf(
      containsPair('userId', userId),
      containsPair('displayName', _names[userId]),
      containsPair('anonymousCount', 0),
    );

    Matcher anonymousNode(int count) => allOf(
      containsPair('userId', null),
      containsPair('displayName', null),
      containsPair('anonymousCount', count),
    );

    // The helper returns canonical named nodes; viewer masking belongs to
    // asMap. Its public API is typed now that the implementation exists.
    Future<List<Map<String, dynamic>>> notificationPath() async {
      final nodes = await harness.pathCase.helpPathFor(
        beaconId: _beaconId,
        helperId: _helperId,
      );
      return [
        for (final node in nodes)
          <String, dynamic>{
            'userId': node.userId,
            'displayName': node.displayName,
            'anonymousCount': node.anonymousCount,
          },
      ];
    }

    Future<void> finalizeRequest() async {
      // One accepted helper cannot peer-vote: close() opens and immediately
      // finalizes a real closure epoch, including settlement and receipts.
      await harness.closureCase.close(
        authorId: _authorId,
        beaconId: _beaconId,
      );
      final closure = ClosureRepository(database);
      final epoch = await closure.latestEpoch(_beaconId);
      expect(epoch, isNotNull);
      expect(epoch!.status, ClosureEpochStatus.finalized);
      expect(epoch.finalizedAt, isNotNull);
      expect(await closure.liveEpoch(_beaconId), isNull);
      expect(
        (await BeaconRepository(
          database,
        ).getBeaconById(beaconId: _beaconId)).status,
        BeaconStatus.closed,
      );
      final members = await closure.members(
        beaconId: _beaconId,
        epoch: epoch.epoch,
      );
      expect(members.map((m) => m.userId), [_helperId]);
      expect(members.single.arrivalEdgeId, 'Fhpath000003');
    }

    Future<void> block(String blocker, String blocked) => writer.execute(
      Sql.named('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@blocker, @blocked, @blocker)
'''),
      parameters: {'blocker': blocker, 'blocked': blocked},
    );

    Future<Map<String, int>> noWriteTableCounts() async => {
      for (final table in _noWriteTables)
        table:
            (await writer.execute(
                  'SELECT count(*) FROM public.$table',
                )).single.single!
                as int,
    };

    group('ordered path', () {
      test('the author gets author, forwarders and helper in route order, '
          'by name', () async {
        await seedThreeHopChain();
        await offerAndAccept();

        final result = await helpPath(_authorId);

        expect(pathOf(result), [
          namedNode(_authorId),
          namedNode(_f1Id),
          namedNode(_f2Id),
          namedNode(_helperId),
        ]);
      }, skip: skipReason);

      test('the path survives the Request being finalized', () async {
        await seedThreeHopChain();
        await offerAndAccept();
        await finalizeRequest();

        expect(idsOf(await helpPath(_authorId)), [
          _authorId,
          _f1Id,
          _f2Id,
          _helperId,
        ]);
        expect(idsOf(await helpPath(_helperId)), [
          _authorId,
          _f1Id,
          _f2Id,
          _helperId,
        ]);
      }, skip: skipReason);

      test('the notification helper and viewer query agree on the accepted '
          'helper arrival route', () async {
        await seedThreeHopChain();
        await offerAndAccept();

        final path = await notificationPath();

        expect(path, [
          namedNode(_authorId),
          namedNode(_f1Id),
          namedNode(_f2Id),
          namedNode(_helperId),
        ]);
        expect(pathOf(await helpPath(_authorId)), path);
        expect(pathOf(await helpPath(_helperId)), path);
      }, skip: skipReason);

      test('the notification helper and viewer query retain the same route '
          'after closure settlement', () async {
        await seedThreeHopChain();
        await offerAndAccept();
        await finalizeRequest();

        final path = await notificationPath();

        expect(path, [
          namedNode(_authorId),
          namedNode(_f1Id),
          namedNode(_f2Id),
          namedNode(_helperId),
        ]);
        expect(pathOf(await helpPath(_authorId)), path);
        expect(pathOf(await helpPath(_helperId)), path);
      }, skip: skipReason);

      test('a cancelled hop in a sibling branch is not on the path', () async {
        await seedThreeHopChain();
        await offerAndAccept();

        final result = await helpPath(_authorId);

        expect(idsOf(result), isNot(contains(_siblingId)));
        expect(idsOf(result), [_authorId, _f1Id, _f2Id, _helperId]);
      }, skip: skipReason);

      test('the edge view used by the forwards graph is still returned next '
          'to the path', () async {
        await seedThreeHopChain();
        await offerAndAccept();

        final result = await helpPath(_authorId);

        final edgeIds = {
          for (final e in (result['edges'] as List<dynamic>))
            (e as Map<String, dynamic>)['id'],
        };
        expect(
          edgeIds,
          containsAll(['Fhpath000001', 'Fhpath000002', 'Fhpath000003']),
        );
        expect(edgeIds, isNot(contains('Fhpath000005')));
        expect(pathOf(result), hasLength(4));
      }, skip: skipReason);
    });

    group('names along the path', () {
      test('GraphQL serves zero anonymous counts for named people and null '
          'identity fields for a blocked person', () async {
        await seedThreeHopChain();
        await offerAndAccept();
        await block(_f1Id, _f2Id);
        final graphQL = GraphQL(
          GraphQLSchema(
            queryType: GraphQLObjectType('Query', null)
              ..fields.addAll(
                QueryHelpOffererForwardPath(
                  beaconHelpOffererForwardPathCase: harness.pathCase,
                ).all,
              ),
          ),
          customTypes: customTypes,
        );

        final result = await graphQL.parseAndExecute(
          '''
query {
  beaconHelpOffererForwardPath(id: "$_beaconId", helpOffererId: "$_helperId") {
    path { userId displayName anonymousCount }
  }
}
''',
          globalVariables: const {kGlobalInputQueryJwt: JwtEntity(sub: _f1Id)},
        );

        expect(result, {
          'beaconHelpOffererForwardPath': {
            'path': [
              {
                'userId': _authorId,
                'displayName': _names[_authorId],
                'anonymousCount': 0,
              },
              {
                'userId': _f1Id,
                'displayName': _names[_f1Id],
                'anonymousCount': 0,
              },
              {'userId': null, 'displayName': null, 'anonymousCount': 1},
              {
                'userId': _helperId,
                'displayName': _names[_helperId],
                'anonymousCount': 0,
              },
            ],
          },
        });
      }, skip: skipReason);

      test('a forwarder sees the next forwarder by name although the two are '
          'not mutually visible, and reading writes no visibility or trust '
          'rows', () async {
        await seedThreeHopChain();
        await offerAndAccept();
        // No MeritRank runs here and nobody voted, so nothing makes F1 and
        // F2 mutually visible; the cache must not claim otherwise.
        final mutual = await writer.execute(
          Sql.named('''
SELECT count(*) FROM public.person_mutual_visibility_cache
WHERE person_lo = least(@a, @b) AND person_hi = greatest(@a, @b)
  AND is_mutually_visible
'''),
          parameters: {'a': _f1Id, 'b': _f2Id},
        );
        expect(
          mutual.single.single,
          0,
          reason: 'precondition: F1 and F2 are not mutually visible',
        );
        final before = await noWriteTableCounts();

        final result = await helpPath(_f1Id);

        expect(pathOf(result), [
          namedNode(_authorId),
          namedNode(_f1Id),
          namedNode(_f2Id),
          namedNode(_helperId),
        ]);
        expect(await noWriteTableCounts(), before);
      }, skip: skipReason);

      test(
        'someone the viewer blocked comes back as one anonymous node',
        () async {
          await seedThreeHopChain();
          await offerAndAccept();
          await block(_f1Id, _f2Id);

          final result = await helpPath(_f1Id);

          expect(pathOf(result), [
            namedNode(_authorId),
            namedNode(_f1Id),
            anonymousNode(1),
            namedNode(_helperId),
          ]);
        },
        skip: skipReason,
      );

      test('someone who blocked the viewer comes back anonymous too', () async {
        await seedThreeHopChain();
        await offerAndAccept();
        await block(_f2Id, _f1Id);

        expect(pathOf(await helpPath(_f1Id)), [
          namedNode(_authorId),
          namedNode(_f1Id),
          anonymousNode(1),
          namedNode(_helperId),
        ]);
      }, skip: skipReason);

      test(
        'two blocked people in a row collapse into one node counting two',
        () async {
          await seedFourHopChain();
          await offerAndAccept();
          await block(_f1Id, _f2Id);
          await block(_f1Id, _f3Id);

          expect(pathOf(await helpPath(_f1Id)), [
            namedNode(_authorId),
            namedNode(_f1Id),
            anonymousNode(2),
            namedNode(_helperId),
          ]);
        },
        skip: skipReason,
      );
    });

    group('who gets the path', () {
      for (final finalized in [false, true]) {
        test(
          'the forwarder before the helper sees the full named path in order '
          '${finalized ? 'after finalization' : 'for an accepted offer'}',
          () async {
            await seedThreeHopChain();
            await offerAndAccept();
            if (finalized) await finalizeRequest();

            final result = await helpPath(_f2Id);

            expect(pathOf(result), [
              namedNode(_authorId),
              namedNode(_f1Id),
              namedNode(_f2Id),
              namedNode(_helperId),
            ]);
          },
          skip: skipReason,
        );
      }

      test('an involved person off the route keeps the edge view without a '
          'path', () async {
        await seedThreeHopChain();
        await offerAndAccept();

        final result = await helpPath(_offPathId);

        expect(result['edges'] as List<dynamic>, isNotEmpty);
        expect(pathOf(result), isEmpty);
      }, skip: skipReason);

      test('a person neither on the route nor involved is refused', () async {
        await seedThreeHopChain();
        await offerAndAccept();

        await expectLater(
          helpPath(_strangerId),
          throwsA(isA<UnauthorizedException>()),
        );
      }, skip: skipReason);

      test('a withdrawn offer is not a help path target, as before', () async {
        await seedThreeHopChain();
        await offerAndAccept();
        await harness.helpOfferCase.withdraw(
          beaconId: _beaconId,
          userId: _helperId,
          withdrawReason: 'timing',
        );

        await expectLater(
          helpPath(_authorId),
          throwsA(isA<IdNotFoundException>()),
        );
      }, skip: skipReason);
    });
  }, skip: skipReason);
}

Future<void> _forward(
  Connection writer,
  String id,
  String senderId,
  String recipientId, {
  required String ago,
  String? parent,
  String? cancelledAgo,
}) => writer.execute('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, parent_edge_id, created_at,
  cancelled_at
) VALUES (
  '$id', '$_beaconId', '$senderId', '$recipientId',
  ${parent == null ? 'NULL' : "'$parent'"},
  now() - interval '$ago',
  ${cancelledAgo == null ? 'NULL' : "now() - interval '$cancelledAgo'"}
)
''');

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.trust_evidence,
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.user_block,
  public.beacon,
  public."user"
CASCADE
''');
  for (final MapEntry(key: id, value: name) in _names.entries) {
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
  '$_beaconId', '$_authorId', 'Help path beacon', 'desc',
  ${BeaconStatus.open.smallintValue}
)
''');
}

final class _Harness {
  const _Harness({
    required this.helpOfferCase,
    required this.coordinationCase,
    required this.pathCase,
    required this.closureCase,
  });

  final HelpOfferCase helpOfferCase;
  final CoordinationCase coordinationCase;
  final BeaconHelpOffererForwardPathCase pathCase;
  final ClosureCase closureCase;

  factory _Harness.build(TenturaDb db, Env env) {
    final logger = Logger('HelpPathOrderedChainPgTest');
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
    final closureRepository = ClosureRepository(db);
    final effects = BeaconLifecycleEffectsCase(
      BeaconHierarchyOutboxRepository(db),
      env: env,
      logger: logger,
    );
    final receipts = ClosureReceiptsRepository(db);
    final closureCase = ClosureCase(
      unitOfWork: unitOfWork,
      closureRepository: closureRepository,
      beaconRepository: beacons,
      commitmentRepository: commitments,
      helpOfferRepository: helpOffers,
      hierarchyRepository: hierarchy,
      lifecycleEffects: effects,
      attentionSystemSettlement: systemSettlement,
      receipts: receipts,
      finalizer: ClosureFinalizeCase(
        unitOfWork: unitOfWork,
        closureRepository: closureRepository,
        beaconRepository: beacons,
        trustLedger: TrustLedgerRepository(db),
        lifecycleEffects: effects,
        attentionSystemSettlement: systemSettlement,
        trustPublisher: TrustPublisherCase(
          TrustPublishRepository(db),
          env: env,
          logger: logger,
        ),
        receipts: receipts,
        env: env,
        logger: logger,
      ),
      env: env,
      logger: logger,
    );
    return _Harness(
      closureCase: closureCase,
      // The case under test runs on the real repositories and the real
      // `beacon_can_read_involvement` guard.
      pathCase: BeaconHelpOffererForwardPathCase(
        beacons,
        ForwardEdgeRepository(db),
        helpOffers,
        access,
        env: env,
        logger: logger,
      ),
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
        closureCase: closureCase,
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
        closureCase: closureCase,
        env: env,
        logger: logger,
      ),
    );
  }
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

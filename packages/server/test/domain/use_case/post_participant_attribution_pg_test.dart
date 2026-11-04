@Tags(['pg'])
library;

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_beacon_room.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/forward_attribution_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/invitation_repository.dart';
import 'package:tentura_server/data/repository/invite_genealogy_repository.dart';
import 'package:tentura_server/data/repository/invite_seed_prompt_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/data/repository/polling_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_contact_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/post_publish_pg_support.dart';

const _alice = 'UoriginAlice';
const _bob = 'UoriginBob01';
const _dave = 'UoriginDave1';
const _legacy = 'UoriginOld01';
const _outsider = 'UoriginOther';
const _post = 'BoriginPost1';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_PARTICIPANT_ATTRIBUTION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_participant_attribution',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb database;
  late Connection writer;
  late BeaconRoomCase room;
  late ForwardCase forwards;
  late InvitationCase invitations;
  late UserRepository users;
  late String eve;
  late String carol;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    room = BeaconRoomCase(
      BeaconRoomRepository(database),
      CoordinationItemRepository(database),
      _UnusedFactCards(),
      _UnusedImages(),
      _UnusedTasks(),
      _UnusedStorage(),
      PollingRepository(database),
      _UnusedQuota(),
      UserBlockRepository(target.databaseEnv, database),
      MutatingUnitOfWork(database),
      FakeBeaconHierarchyRepository(),
      const ProductionDiscussionProductPolicy(),
      beaconRepository: BeaconRepository(database),
      env: target.databaseEnv,
      logger: Logger('PostParticipantAttributionPgTest'),
    );
    final env = target.databaseEnv;
    final logger = Logger('PostParticipantArrivalWorkflows');
    final roomRepository = BeaconRoomRepository(database);
    final beacons = BeaconRepository(database);
    final blocks = UserBlockRepository(env, database);
    final access = BeaconAccessRepository(database);
    final help = HelpOfferRepository(database);
    final edges = ForwardEdgeRepository(database);
    final postLock = PostLockRepository(database);
    users = UserRepository(
      env,
      database,
      InviteGenealogyRepository(env, database, blocks),
      InviteSeedPromptRepository(database),
    );
    final attention = TransactionalAttentionCase(
      MutatingUnitOfWork(database),
      AttentionDispatchRepository(database, logger),
    );
    final intents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(
        roomRepository,
        database,
        help,
        CommitmentRepository(database),
      ),
      users,
      access,
      blocks,
    );
    forwards = ForwardCase(
      edges,
      ForwardAttributionRepository(database),
      help,
      InboxRepository(database),
      CapabilityEvidenceRepository(database),
      beacons,
      blocks,
      PersonVisibilityRepository(database),
      access,
      postLock: postLock,
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    );
    invitations = InvitationCase(
      InvitationRepository(database),
      users,
      beacons,
      VoteUserFriendshipLookup(database),
      UserContactRepository(database),
      access,
      edges,
      blocks,
      postLock: postLock,
      room: roomRepository,
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    );
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  setUp(() async {
    await writer.execute('TRUNCATE public."user" CASCADE');
    for (final (index, id) in [
      _alice,
      _bob,
      _dave,
      _legacy,
      _outsider,
    ].indexed) {
      await writer.execute(
        Sql.named('''
          INSERT INTO public."user" (id, display_name, public_key)
          VALUES (@id, @name, @key)'''),
        parameters: {
          'id': id,
          'name': 'Name $id',
          'key': pgTestPublicKey('post-participant-attribution', index + 1),
        },
      );
    }
    await writer.execute('''
      INSERT INTO public.beacon
        (id, user_id, title, description, status, kind, forward_policy,
         is_discoverable)
      VALUES ('$_post', '$_alice', '', '', 3, 1, 1, false)
    ''');
    // Direct forwarding requires reciprocal visibility in the real workflow.
    for (final (sender, recipient) in [(_alice, _bob), (_bob, _dave)]) {
      await writer.execute(
        Sql.named('''
          INSERT INTO public.vote_user (subject, object, amount)
          VALUES (@sender, @recipient, 1), (@recipient, @sender, 1)'''),
        parameters: {'sender': sender, 'recipient': recipient},
      );
    }
    final published =
        await PostPublishHarness.build(
          database,
          target.databaseEnv,
        ).posts.publish(
          authorId: _alice,
          beaconId: _post,
          body: 'A Post shared with Bob',
          mentionUserIds: const [],
          mentionOffsets: const [],
          mentionLengths: const [],
          recipientIds: const [_bob],
          notes: const {},
          forwardPolicy: BeaconForwardPolicyValue.open,
        );
    expect(published.beaconId, _post);

    final eveInvite = await invitations.create(
      userId: _bob,
      addresseeName: 'Eve',
      beaconId: _post,
    );
    eve = (await users.createInvited(
      invitationId: eveInvite.id,
      publicKey: pgTestPublicKey('post-participant-attribution', 6),
      displayName: 'Eve',
    )).id;
    final carolInvite = await invitations.create(
      userId: _alice,
      addresseeName: 'Carol',
      beaconId: _post,
    );
    carol = (await users.createInvited(
      invitationId: carolInvite.id,
      publicKey: pgTestPublicKey('post-participant-attribution', 7),
      displayName: 'Carol',
    )).id;
    final delivered = await forwards.forward(
      senderId: _bob,
      beaconId: _post,
      recipientIds: [_dave],
    );
    expect(delivered.deliveredRecipientIds, [_dave]);

    // A later forward to Eve must not replace Bob's accepted signup invite.
    await writer.execute(
      Sql.named('''
          INSERT INTO public.vote_user (subject, object, amount)
        VALUES (@alice, @eve, 1), (@eve, @alice, 1)'''),
      parameters: {'alice': _alice, 'eve': eve},
    );
    final laterForward = await forwards.forward(
      senderId: _alice,
      beaconId: _post,
      recipientIds: [eve],
    );
    expect(laterForward.deliveredRecipientIds, [eve]);
    // Dave accepts Carol's invite after Bob has already forwarded the Post.
    final laterInvite = await invitations.create(
      userId: carol,
      addresseeName: 'Dave',
      beaconId: _post,
    );
    expect(
      await invitations.acceptAsExisting(code: laterInvite.id, userId: _dave),
      isTrue,
    );

    // Verify the workflows actually persisted accepted invites and both
    // arrival paths, rather than supplying attribution as test-authored data.
    final accepted = await writer.execute(
      Sql.named('''
        SELECT user_id, invited_id, invite_origin
        FROM public.invitation WHERE beacon_id = @post
        AND accepted_at IS NOT NULL'''),
      parameters: {'post': _post},
    );
    expect(
      accepted.map((row) => row.toList()),
      unorderedEquals([
        [_bob, eve, 'new_account'],
        [_alice, carol, 'new_account'],
        [carol, _dave, 'existing_account'],
      ]),
    );
    final daveEdges = await writer.execute(
      Sql.named('''
        SELECT sender_id FROM public.beacon_forward_edge
        WHERE beacon_id = @post AND recipient_id = @dave
        ORDER BY created_at'''),
      parameters: {'post': _post, 'dave': _dave},
    );
    expect(daveEdges.map((row) => row.single), [_bob, carol]);

    // Explicit participant rows for the author and a historical member have
    // no arrival event. These fixtures exercise null attribution; all invite
    // and forward arrival records above come from the production workflows.
    await writer.execute('''
      INSERT INTO public.beacon_participant
        (id, beacon_id, user_id, role, status, room_access)
      VALUES ('PoriginAuth1', '$_post', '$_alice', 0, 0, 3),
             ('PoriginOld01', '$_post', '$_legacy', 6, 0, 3)
    ''');
  });

  group('Post participant arrival attribution', () {
    for (final sample in [
      (
        member: () => eve,
        source: _bob,
        how: 'invite',
        label: 'a member invited by a forwarding recipient',
      ),
      (
        member: () => carol,
        source: _alice,
        how: 'invite',
        label: 'a member invited by the author',
      ),
      (
        member: () => _dave,
        source: _bob,
        how: 'forward',
        label: 'an existing user reached by forward before a later invite',
      ),
    ]) {
      test('the author sees who brought ${sample.label}', () async {
        // Check denial on the same real read path before checking member data.
        await expectLater(
          room.listParticipants(beaconId: _post, userId: _outsider),
          throwsA(isA<UnauthorizedException>()),
        );
        final rows = await room.listParticipants(
          beaconId: _post,
          userId: _alice,
        );
        for (final id in [_alice, _legacy]) {
          final row = rows.singleWhere((row) => row['userId'] == id);
          expect(row['broughtById'], isNull);
          expect(row['broughtBy'], isNull);
          expect(row['broughtHow'], isNull);
        }
        final row = rows.singleWhere((row) => row['userId'] == sample.member());
        expect(row, containsPair('broughtById', sample.source));
        expect(
          row,
          containsPair('broughtBy', {
            'userId': sample.source,
            'displayName': 'Name ${sample.source}',
          }),
        );
        expect(row, containsPair('broughtHow', sample.how));
      });
    }

    test(
      'a member sees the first arrival source of peers they did not invite or forward to',
      () async {
        final rows = await room.listParticipants(
          beaconId: _post,
          userId: carol,
        );
        expect(
          rows.singleWhere((row) => row['userId'] == eve),
          allOf(
            containsPair('broughtById', _bob),
            containsPair('broughtBy', {
              'userId': _bob,
              'displayName': 'Name $_bob',
            }),
            containsPair('broughtHow', 'invite'),
          ),
        );
        expect(
          rows.singleWhere((row) => row['userId'] == _dave),
          allOf(
            containsPair('broughtById', _bob),
            containsPair('broughtHow', 'forward'),
          ),
        );
      },
    );

    test(
      'a forwarding member sees attribution for a peer invited by the author',
      () async {
        final rows = await room.listParticipants(
          beaconId: _post,
          userId: _bob,
        );
        expect(
          rows.singleWhere((row) => row['userId'] == carol),
          allOf(
            containsPair('broughtById', _alice),
            containsPair('broughtBy', {
              'userId': _alice,
              'displayName': 'Name $_alice',
            }),
            containsPair('broughtHow', 'invite'),
          ),
        );
      },
    );

    test(
      'outsiders are denied the arrival attribution visible to an unrelated admitted member',
      () async {
        await expectLater(
          room.listParticipants(beaconId: _post, userId: _outsider),
          throwsA(isA<UnauthorizedException>()),
        );
        // This member has never sent or received any recorded arrival edge.
        final rows = await room.listParticipants(
          beaconId: _post,
          userId: _legacy,
        );
        expect(
          rows.singleWhere((row) => row['userId'] == eve),
          allOf(
            containsPair('broughtById', _bob),
            containsPair('broughtBy', {
              'userId': _bob,
              'displayName': 'Name $_bob',
            }),
            containsPair('broughtHow', 'invite'),
          ),
        );
        expect(
          rows.singleWhere((row) => row['userId'] == _dave),
          allOf(
            containsPair('broughtById', _bob),
            containsPair('broughtBy', {
              'userId': _bob,
              'displayName': 'Name $_bob',
            }),
            containsPair('broughtHow', 'forward'),
          ),
        );
      },
    );

    test(
      'the GraphQL participant query exposes arrival identity and method',
      () async {
        final graphQL = GraphQL(
          GraphQLSchema(
            queryType: GraphQLObjectType('Query', null)
              ..fields.add(
                QueryBeaconRoom(beaconRoomCase: room).beaconParticipantList,
              ),
          ),
        );
        final execution = graphQL.parseAndExecute(
          '''
        { BeaconParticipantList(beaconId: "$_post") {
          userId broughtById broughtBy { userId displayName } broughtHow
        } }''',
          globalVariables: {kGlobalInputQueryJwt: const JwtEntity(sub: _alice)},
        );
        // graphql_server2 throws GraphQLException for execution errors;
        // parseAndExecute returns a data map, not an HTTP data/errors envelope.
        await expectLater(execution, completes);
        final response = switch (await execution) {
          final Map<String, Object?> data => data,
          _ => fail('GraphQL must return a data map'),
        };
        expect(response, isNot(contains('errors')));
        final rows = switch (response['BeaconParticipantList']) {
          final List<Object?> values => [
            for (final value in values)
              switch (value) {
                final Map<String, Object?> row => row,
                _ => fail('Each participant must be an object'),
              },
          ],
          _ => fail('BeaconParticipantList must be a non-null list'),
        };
        expect(rows, hasLength(6));
        expect(
          response,
          containsPair(
            'BeaconParticipantList',
            allOf([
              contains(
                equals({
                  'userId': eve,
                  'broughtById': _bob,
                  'broughtBy': {'userId': _bob, 'displayName': 'Name $_bob'},
                  'broughtHow': 'invite',
                }),
              ),
              contains(
                equals({
                  'userId': _dave,
                  'broughtById': _bob,
                  'broughtBy': {'userId': _bob, 'displayName': 'Name $_bob'},
                  'broughtHow': 'forward',
                }),
              ),
              contains(
                equals({
                  'userId': carol,
                  'broughtById': _alice,
                  'broughtBy': {
                    'userId': _alice,
                    'displayName': 'Name $_alice',
                  },
                  'broughtHow': 'invite',
                }),
              ),
            ]),
          ),
        );
        for (final id in [_alice, _legacy]) {
          final row = rows.singleWhere(
            (row) => row['userId'] == id,
          );
          expect(row['broughtById'], isNull);
          expect(row['broughtBy'], isNull);
          expect(row['broughtHow'], isNull);
        }
      },
    );
  });
}

final class _UnusedFactCards extends Fake
    implements BeaconFactCardRepositoryPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedTasks extends Fake implements TaskRepositoryPort {}

final class _UnusedStorage extends Fake implements RemoteStoragePort {}

final class _UnusedQuota extends Fake implements UploadQuotaRepositoryPort {}

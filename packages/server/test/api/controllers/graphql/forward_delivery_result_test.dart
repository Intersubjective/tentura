@Tags(['pg'])
library;

import 'dart:io';

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_forward.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/capability_evidence_port.dart';
import 'package:tentura_server/domain/port/forward_attribution_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/fake_beacon_access_guard.dart';
import '../../../support/fake_user_block_repository.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/test_attention_harness.dart';
import '../../../domain/use_case/forward_case_mocks.mocks.dart';

String _baseTypeName(GraphQLType type) {
  var t = type;
  while (true) {
    if (t is GraphQLNonNullableType) {
      t = t.ofType;
    } else if (t is GraphQLListType) {
      t = t.ofType;
    } else {
      return t.name ?? t.toString();
    }
  }
}

bool _isNonNullable(GraphQLType type) => type is GraphQLNonNullableType;

GraphQL _forwardGraphQL(MutationForward mutation) => GraphQL(
  GraphQLSchema(
    queryType: GraphQLObjectType('Query', 'Query root')
      ..fields.add(
        GraphQLObjectField(
          '_health',
          graphQLBoolean.nonNullable(),
          resolve: (_, __) => true,
        ),
      ),
    mutationType: GraphQLObjectType('Mutation', 'Mutation root')
      ..fields.addAll(mutation.all),
  ),
);

Future<Map<String, dynamic>> _executeDocument({
  required GraphQL graphQL,
  required String document,
  Map<String, dynamic> variables = const {},
  JwtEntity? jwt,
  String? operationName,
}) async {
  final result = await graphQL.parseAndExecute(
    document,
    operationName: operationName,
    variableValues: variables,
    globalVariables: {
      if (jwt != null) kGlobalInputQueryJwt: jwt,
    },
  );
  return result as Map<String, dynamic>;
}

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('ForwardDeliveryResult GraphQL schema', () {
    late ForwardCase forwardCase;
    late MutationForward mutation;

    setUp(() {
      final forwardEdgeRepo = MockForwardEdgeRepositoryPort();
      final forwardAttributionRepo = MockForwardAttributionRepositoryPort();
      final helpOfferRepo = MockHelpOfferRepositoryPort();
      final inboxRepo = MockInboxRepositoryPort();
      final capabilityEvidence = MockCapabilityEvidencePort();
      final beaconRepo = MockBeaconRepositoryPort();
      final personVisibilityRepo = MockPersonVisibilityRepositoryPort();

      forwardCase = ForwardCase(
        forwardEdgeRepo,
        forwardAttributionRepo,
        helpOfferRepo,
        inboxRepo,
        capabilityEvidence,
        beaconRepo,
        FakeUserBlockRepository(),
        personVisibilityRepo,
        FakeBeaconAccessGuard(),
        env: Env(environment: Environment.test),
        logger: Logger('ForwardDeliveryResultSchemaTest'),
      );
      mutation = MutationForward(forwardCase: forwardCase);
    });

    test('beaconForward is non-null ForwardDeliveryResult with three fields', () {
      final field = mutation.forward;
      expect(field.name, 'beaconForward');
      expect(field.type, isA<GraphQLNonNullableType>());
      final resultType =
          (field.type as GraphQLNonNullableType).ofType as GraphQLObjectType;
      expect(resultType.name, 'ForwardDeliveryResult');
      expect(resultType, same(gqlTypeForwardDeliveryResult));

      final fieldNames = resultType.fields.map((f) => f.name).toSet();
      expect(
        fieldNames,
        {
          'batchId',
          'deliveredRecipientIds',
          'availabilitySkippedRecipientIds',
        },
      );
      for (final graphField in resultType.fields) {
        expect(graphField.type, isA<GraphQLNonNullableType>());
        if (graphField.name == 'batchId') {
          expect(_baseTypeName(graphField.type), 'String');
        } else {
          expect(_baseTypeName(graphField.type), 'String');
          expect(
            (graphField.type as GraphQLNonNullableType).ofType,
            isA<GraphQLListType>(),
          );
          final listType =
              (graphField.type as GraphQLNonNullableType).ofType
                  as GraphQLListType;
          expect(_isNonNullable(listType.ofType), isTrue);
        }
      }
    });
  });

  group('beaconForward document execution — ForwardDeliveryResult parity', () {
    late Connection writer;
    late TenturaDb db;
    late ForwardEdgeRepository forwardRepo;
    late UserAvailabilityRepository availabilityRepo;
    late ForwardCase forwardCase;
    late TestAttentionHarness attention;
    late MutationForward mutation;
    late GraphQL graphQL;

    const beaconId = 'Bfwdrgql00001';
    const authorId = 'Ufwdrgauth001';
    const senderId = 'Ufwdrgsend001';
    const openRecipient = 'Ufwdrgopen001';
    const pausedRecipient1 = 'Ufwdrgpauz001';
    const limitedRecipient = 'Ufwdrglim0001';
    const pausedRecipient2 = 'Ufwdrgpauz002';
    const dedupRecipient = 'Ufwdrgdup0001';
    final futureResumeOn = DateTime.utc(2026, 9, 15);

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

      db = TenturaDb(target.databaseEnv);
      if (!await _hasUserAvailabilityTable(db)) {
        throw StateError('m0148 schema (user_availability) missing');
      }
      forwardRepo = ForwardEdgeRepository(db);
      availabilityRepo = UserAvailabilityRepository(db);
      final beaconRepo = BeaconRepository(db);
      final helpOfferRepo = HelpOfferRepository(db);
      attention = TestAttentionHarness();

      forwardCase = ForwardCase(
        forwardRepo,
        _NoopForwardAttribution(),
        helpOfferRepo,
        _NoopInbox(),
        _NoopCapabilityEvidence(),
        beaconRepo,
        FakeUserBlockRepository(),
        _AllVisiblePeers(),
        FakeBeaconAccessGuard(),
        attentionIntents: attention.intents,
        attention: attention.transactional,
        env: target.databaseEnv,
        logger: Logger('ForwardDeliveryResultGraphQLTest'),
      );
      mutation = MutationForward(forwardCase: forwardCase);
      graphQL = _forwardGraphQL(mutation);
    });

    setUp(() async {
      if (skipReason != false) {
        return;
      }
      await writer.execute(
        "DELETE FROM public.beacon_forward_edge WHERE beacon_id = '$beaconId'",
      );
      await writer.execute(
        "DELETE FROM public.user_availability WHERE user_id LIKE 'Ufwdrg%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon WHERE id = '$beaconId'",
      );
      await writer.execute(
        '''DELETE FROM public."user" WHERE id LIKE 'Ufwdrg%' ''',
      );
      await _seedFixture(writer);
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await db.close();
      await writer.close();
      await target.drop();
    });

    Future<List<String>> deliveredRecipientIdsForBatch(String batchId) async {
      final rows = await writer.execute(
        Sql.named(r'''
SELECT recipient_id
FROM public.beacon_forward_edge
WHERE batch_id = @batchId
  AND cancelled_at IS NULL
ORDER BY created_at ASC, recipient_id ASC
'''),
        parameters: {'batchId': batchId},
      );
      return rows.map((row) => row[0]! as String).toList();
    }

    Future<int> activeEdgeCount({
      required String sender,
      required String recipient,
    }) async {
      final rows = await writer.execute(
        Sql.named(r'''
SELECT COUNT(*)::int
FROM public.beacon_forward_edge
WHERE beacon_id = @beaconId
  AND sender_id = @senderId
  AND recipient_id = @recipientId
  AND cancelled_at IS NULL
'''),
        parameters: {
          'beaconId': beaconId,
          'senderId': sender,
          'recipientId': recipient,
        },
      );
      return rows.single.single! as int;
    }

    test(
      'mixed beaconForward document matches inserted rows and attention effects',
      () async {
        await availabilityRepo.pause(
          userId: pausedRecipient1,
          resumeOn: futureResumeOn,
        );
        await availabilityRepo.pause(
          userId: pausedRecipient2,
          resumeOn: futureResumeOn,
        );
        await availabilityRepo.setLimited(
          userId: limitedRecipient,
          isLimited: true,
        );

        final preexisting = await forwardRepo.createBatch(
          beaconId: beaconId,
          senderId: senderId,
          recipientIds: [dedupRecipient],
          batchId: 'batch-fwdrgql-preexisting',
          noteForRecipient: (_) => 'preexisting edge',
        );
        expect(preexisting.createdEdges, hasLength(1));
        expect(
          await activeEdgeCount(sender: senderId, recipient: dedupRecipient),
          1,
        );

        attention.recorded.clear();

        final recipientIds = [
          openRecipient,
          pausedRecipient1,
          limitedRecipient,
          pausedRecipient2,
          dedupRecipient,
        ];

        final result = await _executeDocument(
          graphQL: graphQL,
          document: r'''
            mutation ForwardDeliveryResultParity(
              $id: String!
              $recipientIds: [String!]!
            ) {
              beaconForward(id: $id, recipientIds: $recipientIds) {
                batchId
                deliveredRecipientIds
                availabilitySkippedRecipientIds
              }
            }
          ''',
          variables: {
            'id': beaconId,
            'recipientIds': recipientIds,
          },
          jwt: const JwtEntity(sub: senderId),
          operationName: 'ForwardDeliveryResultParity',
        );

        final payload = result['beaconForward'] as Map<String, dynamic>;
        final batchId = payload['batchId'] as String;
        final deliveredRecipientIds = List<String>.from(
          payload['deliveredRecipientIds'] as List,
        );
        final availabilitySkippedRecipientIds = List<String>.from(
          payload['availabilitySkippedRecipientIds'] as List,
        );

        expect(batchId, isNotEmpty);

        final insertedRecipientIds = await deliveredRecipientIdsForBatch(
          batchId,
        );
        expect(insertedRecipientIds.toSet(), deliveredRecipientIds.toSet());
        expect(deliveredRecipientIds, [openRecipient, limitedRecipient]);

        expect(
          availabilitySkippedRecipientIds,
          [pausedRecipient1, pausedRecipient2],
        );

        expect(
          await activeEdgeCount(sender: senderId, recipient: openRecipient),
          1,
        );
        expect(
          await activeEdgeCount(sender: senderId, recipient: limitedRecipient),
          1,
        );
        expect(
          await activeEdgeCount(
            sender: senderId,
            recipient: pausedRecipient1,
          ),
          0,
        );
        expect(
          await activeEdgeCount(
            sender: senderId,
            recipient: pausedRecipient2,
          ),
          0,
        );
        expect(
          await activeEdgeCount(sender: senderId, recipient: dedupRecipient),
          1,
        );
        expect(
          deliveredRecipientIds,
          isNot(contains(dedupRecipient)),
        );
        expect(
          availabilitySkippedRecipientIds,
          isNot(contains(dedupRecipient)),
        );

        expect(attention.recorded, hasLength(1));
        final intent = attention.recorded.single;
        expect(intent.eventType.name, 'relayReceived');
        expect(
          intent.recipients.map((recipient) => recipient.recipientId),
          deliveredRecipientIds,
        );
        expect(intent.sourceEventKey, 'forward_batch:$batchId');
      },
      skip: skipReason,
    );
  });
}

Future<void> _seedFixture(Connection writer) async {
  final keyAuthor = pgTestPublicKey('fwdrgql', 1);
  final keySender = pgTestPublicKey('fwdrgql', 2);
  final keyOpen = pgTestPublicKey('fwdrgql', 3);
  final keyPaused1 = pgTestPublicKey('fwdrgql', 4);
  final keyLimited = pgTestPublicKey('fwdrgql', 5);
  final keyPaused2 = pgTestPublicKey('fwdrgql', 6);
  final keyDedup = pgTestPublicKey('fwdrgql', 7);

  await writer.execute(
    Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ('Ufwdrgauth001', 'Author', @keyAuthor, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdrgsend001', 'Sender', @keySender, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdrgopen001', 'Open recipient', @keyOpen, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdrgpauz001', 'Paused recipient 1', @keyPaused1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdrglim0001', 'Limited recipient', @keyLimited, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdrgpauz002', 'Paused recipient 2', @keyPaused2, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdrgdup0001', 'Dedup recipient', @keyDedup, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  public_key = EXCLUDED.public_key
'''),
    parameters: {
      'keyAuthor': keyAuthor,
      'keySender': keySender,
      'keyOpen': keyOpen,
      'keyPaused1': keyPaused1,
      'keyLimited': keyLimited,
      'keyPaused2': keyPaused2,
      'keyDedup': keyDedup,
    },
  );
  await writer.execute(r'''
INSERT INTO public.beacon (id, user_id, title, description, status, created_at, updated_at)
VALUES (
  'Bfwdrgql00001',
  'Ufwdrgauth001',
  'Forward delivery result GraphQL parity',
  '',
  0,
  '2026-01-01T00:00:00Z',
  '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO NOTHING
''');
}

Future<bool> _hasUserAvailabilityTable(TenturaDb db) async {
  final row = await db
      .customSelect(
        '''
SELECT EXISTS (
  SELECT 1
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND table_name = 'user_availability'
) AS present
''',
      )
      .getSingle();
  return row.read<bool>('present');
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

class _AllVisiblePeers extends Fake implements PersonVisibilityRepositoryPort {
  @override
  Future<Set<String>> mutuallyVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  }) async =>
      peerIds.toSet();
}

class _NoopForwardAttribution extends Fake
    implements ForwardAttributionRepositoryPort {}

class _NoopInbox extends Fake implements InboxRepositoryPort {
  @override
  Future<void> upsertWatchingForSender({
    required String senderId,
    required String beaconId,
    String? context,
    bool touchForwardOrdering = true,
  }) async {}

  @override
  Future<void> markForwardCancelledForRecipient({
    required String beaconId,
    required String recipientId,
  }) async {}
}

class _NoopCapabilityEvidence extends Fake implements CapabilityEvidencePort {
  @override
  Future<void> reconcileForwardReasons({
    required String forwardEdgeId,
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  }) async {}
}

class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_FORWARD_DELIVERY_RESULT_TEST_DB'] ??
        'tentura_test_fwdrgql_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_FORWARD_DELIVERY_RESULT_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );

    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await connection.close();
    }
  }

  Future<void> drop() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }
}

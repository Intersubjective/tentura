import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_beacon_room.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/coordination_item_record_fixtures.dart';
import '../../../support/fake_beacon_hierarchy_repository.dart';
import '../../../support/fake_user_block_repository.dart';
import '../../../support/test_attention_harness.dart';

const _beaconId = 'Bbeacon';
const _userId = 'Uauthor';
const _factId = 'Ffact';
const _messageId = 'Rmessage';

class _StubItems extends Fake implements CoordinationItemRepositoryPort {}

class _FakeFactCards extends Fake implements BeaconFactCardRepositoryPort {}

class _FakeImages extends Fake implements ImageRepositoryPort {}

class _FakeTasks extends Fake implements TaskRepositoryPort {}

class _FakeRemoteStorage extends Fake implements RemoteStoragePort {}

class _FakePolling extends Fake implements PollingRepositoryPort {}

class _FakeUploadQuota extends Fake implements UploadQuotaRepositoryPort {}

/// Captures the columns [BeaconRoomCase.createMessage] asked the repository
/// port to persist — the same seam `beacon_room_case_quote_test.dart` uses to
/// prove the domain layer forwards the quote pair.
class _StubRoom extends Fake implements BeaconRoomRepositoryPort {
  BeaconParticipantRecord? participant;

  int insertCalls = 0;
  String? insertedQuotedFactCardId;
  int? insertedQuotedFactRevisionSeq;

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async => false;

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async => false;

  @override
  Future<BeaconParticipantRecord?> findParticipant({
    required String beaconId,
    required String userId,
  }) async => participant;

  @override
  Future<String?> beaconAuthorUserId(String beaconId) async => null;

  @override
  Future<int> countRecentMessagesByAuthor({
    required String authorId,
    required Duration window,
  }) async => 0;

  @override
  Future<List<AdmittedRoomMentionParticipant>> listAdmittedMentionParticipants(
    String beaconId,
  ) async => const [];

  @override
  Future<List<String>> resolveMentionUserIdsForBeacon({
    required String beaconId,
    required String body,
  }) async => const [];

  @override
  Future<BeaconRoomMessageRecord> insertRoomMessage({
    required String beaconId,
    required String authorId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
    String? linkedParticipantId,
    String? linkedPollingId,
    int? semanticMarker,
    Map<String, Object?>? systemPayload,
    List<String> mentions = const [],
    List<Map<String, Object?>> mentionSpans = const [],
    String? quotedFactCardId,
    int? quotedFactRevisionSeq,
  }) async {
    insertCalls++;
    insertedQuotedFactCardId = quotedFactCardId;
    insertedQuotedFactRevisionSeq = quotedFactRevisionSeq;
    return BeaconRoomMessageRecord(
      id: _messageId,
      beaconId: beaconId,
      authorId: authorId,
      body: body,
      createdAt: DateTime.utc(2026),
      quotedFactCardId: quotedFactCardId,
      quotedFactRevisionSeq: quotedFactRevisionSeq,
    );
  }
}

String _baseName(GraphQLType<dynamic, dynamic> t) =>
    t is GraphQLNonNullableType ? (t.ofType.name ?? '') : (t.name ?? '');

/// tentura-85o (issue #181 plan §8.11): `RoomMessageCreate` must declare and
/// forward the quoted-fact pair so a create-with-quote request is not
/// rejected as an unknown argument. The domain layer already supports both
/// args (see beacon_room_case_quote_test.dart); only the resolver is missing.
void main() {
  const jwt = JwtEntity(sub: _userId);

  late _StubRoom room;
  late MutationBeaconRoom mutation;

  setUp(() {
    room = _StubRoom()
      ..participant = testBeaconParticipant(
        beaconId: _beaconId,
        userId: _userId,
      );
    final attention = TestAttentionHarness();
    final beaconRoomCase = BeaconRoomCase(
      room,
      _StubItems(),
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
      attentionIntents: attention.intents,
      attention: attention.transactional,
      env: Env(environment: Environment.test),
      logger: Logger('MutationBeaconRoomQuoteTest'),
    );
    mutation = MutationBeaconRoom(beaconRoomCase: beaconRoomCase);
  });

  test(
    'RoomMessageCreate declares quotedFactCardId and quotedFactRevisionSeq '
    'as nullable arguments',
    () {
      final field = mutation.all.singleWhere(
        (f) => f.name == 'RoomMessageCreate',
      );

      final quotedFactCardId = field.inputs.singleWhere(
        (a) => a.name == 'quotedFactCardId',
        orElse: () => fail(
          'RoomMessageCreate is missing the quotedFactCardId argument',
        ),
      );
      expect(
        quotedFactCardId.type,
        isNot(isA<GraphQLNonNullableType<dynamic, dynamic>>()),
      );
      expect(_baseName(quotedFactCardId.type), 'String');

      final quotedFactRevisionSeq = field.inputs.singleWhere(
        (a) => a.name == 'quotedFactRevisionSeq',
        orElse: () => fail(
          'RoomMessageCreate is missing the quotedFactRevisionSeq argument',
        ),
      );
      expect(
        quotedFactRevisionSeq.type,
        isNot(isA<GraphQLNonNullableType<dynamic, dynamic>>()),
      );
      expect(_baseName(quotedFactRevisionSeq.type), 'Int');
    },
  );

  GraphQL buildGraphQL() => GraphQL(
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

  Future<Map<String, dynamic>> run(
    String document,
    Map<String, dynamic> variables,
  ) async {
    final result =
        await buildGraphQL().parseAndExecute(
              document,
              variableValues: variables,
              globalVariables: {kGlobalInputQueryJwt: jwt},
            )
            as Map<String, dynamic>;
    return result['RoomMessageCreate'] as Map<String, dynamic>;
  }

  const withQuote = r'''mutation($b: String!, $body: String!, $fc: String, $seq: Int) {
    RoomMessageCreate(beaconId: $b, body: $body, quotedFactCardId: $fc, quotedFactRevisionSeq: $seq) {
      id
    }
  }''';

  test(
    'resolver forwards quotedFactCardId and quotedFactRevisionSeq to '
    'BeaconRoomCase.createMessage, which persists them on the row',
    () async {
      final data = await run(withQuote, {
        'b': _beaconId,
        'body': 'about this',
        'fc': _factId,
        'seq': 3,
      });

      expect(data, {'id': _messageId});
      expect(room.insertCalls, 1);
      expect(room.insertedQuotedFactCardId, _factId);
      expect(room.insertedQuotedFactRevisionSeq, 3);
    },
  );
}

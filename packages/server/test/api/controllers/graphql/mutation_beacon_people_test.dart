import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/_mutations_all.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_beacon_people.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/beacon_people_seen_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_people_seen_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/smoke_env.dart';

class _StubRoom extends Fake implements BeaconRoomRepositoryPort {
  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async => true;

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async => false;
}

class _StubSeen extends Fake implements BeaconPeopleSeenRepositoryPort {
  final calls = <({String userId, String beaconId, DateTime at})>[];

  final persisted = DateTime.utc(2026, 6, 15, 12, 30);

  @override
  Future<DateTime> markSeen({
    required String userId,
    required String beaconId,
    required DateTime at,
  }) async {
    calls.add((userId: userId, beaconId: beaconId, at: at));
    return persisted;
  }
}

const _kName = 'MarkBeaconPeopleSeen';

String _baseName(GraphQLType<dynamic, dynamic> t) =>
    t is GraphQLNonNullableType ? (t.ofType.name ?? '') : (t.name ?? '');

void _expectMarkField(GraphQLObjectField<dynamic, dynamic> field) {
  expect(field.type, isA<GraphQLNonNullableType<dynamic, dynamic>>());
  expect(_baseName(field.type), 'BeaconPeopleSeenResult');

  final result =
      (field.type as GraphQLNonNullableType<dynamic, dynamic>).ofType
          as GraphQLObjectType;
  for (final name in const ['beaconId', 'seenAt']) {
    final f = result.fields.singleWhere((f) => f.name == name);
    expect(
      f.type,
      isA<GraphQLNonNullableType<dynamic, dynamic>>(),
      reason: name,
    );
    expect(_baseName(f.type), 'String', reason: name);
  }

  final beaconId = field.inputs.singleWhere((a) => a.name == 'beaconId');
  expect(beaconId.type, isA<GraphQLNonNullableType<dynamic, dynamic>>());
  expect(_baseName(beaconId.type), 'String');

  final readThrough = field.inputs.singleWhere(
    (a) => a.name == 'readThroughAt',
  );
  expect(
    readThrough.type,
    isNot(isA<GraphQLNonNullableType<dynamic, dynamic>>()),
  );
  expect(_baseName(readThrough.type), 'String');
}

void main() {
  const jwt = JwtEntity(sub: 'Uauthor');

  late _StubSeen seen;
  late MutationBeaconPeople mutation;

  setUp(() {
    seen = _StubSeen();
    mutation = MutationBeaconPeople(
      beaconPeopleSeenCase: BeaconPeopleSeenCase(
        _StubRoom(),
        seen,
        env: Env(environment: Environment.test),
        logger: Logger('MutationBeaconPeopleTest'),
      ),
    );
  });

  test('all exposes MarkBeaconPeopleSeen with the expected signature', () {
    _expectMarkField(mutation.all.singleWhere((f) => f.name == _kName));
  });

  test('mutationsAll (evaluated) contains MarkBeaconPeopleSeen', () async {
    final env = smokeDevEnv();
    if (!await smokePostgresReachable(env)) {
      markTestSkipped(
        'Postgres not reachable; mutationsAll DI smoke needs TaskWorker',
      );
      return;
    }
    addTearDown(() async => getIt.reset());
    await configureDependencies(env);
    await getIt.allReady(ignorePendingAsyncCreation: true);

    final matches = mutationsAll.where((f) => f.name == _kName).toList();
    expect(matches, hasLength(1));
    _expectMarkField(matches.single);
  });

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
    String document, [
    Map<String, dynamic> variables = const {},
  ]) async {
    final result =
        await buildGraphQL().parseAndExecute(
              document,
              variableValues: variables,
              globalVariables: {kGlobalInputQueryJwt: jwt},
            )
            as Map<String, dynamic>;
    return result['MarkBeaconPeopleSeen'] as Map<String, dynamic>;
  }

  const withVars = r'''mutation($b: String!, $r: String) {
    MarkBeaconPeopleSeen(beaconId: $b, readThroughAt: $r) {
      beaconId
      seenAt
    }
  }''';

  test('resolver delegates to the case and returns its payload', () async {
    final data = await run(withVars, {
      'b': 'Bbeacon',
      'r': '2026-06-15T12:00:00Z',
    });

    expect(data, {
      'beaconId': 'Bbeacon',
      'seenAt': '2026-06-15T12:30:00.000Z',
    });
    expect(seen.calls, hasLength(1));
    expect(seen.calls.single.userId, 'Uauthor');
    expect(seen.calls.single.beaconId, 'Bbeacon');
    expect(seen.calls.single.at, DateTime.utc(2026, 6, 15, 12));
  });

  for (final (label, doc, vars) in [
    (
      'omitted',
      r'''mutation($b: String!) {
        MarkBeaconPeopleSeen(beaconId: $b) { beaconId seenAt }
      }''',
      <String, dynamic>{'b': 'Bbeacon'},
    ),
    (
      'null',
      withVars,
      <String, dynamic>{'b': 'Bbeacon', 'r': null},
    ),
  ]) {
    test('readThroughAt $label is accepted and defaults to now', () async {
      final before = DateTime.timestamp();
      final data = await run(doc, vars);
      final after = DateTime.timestamp();

      expect(data, {
        'beaconId': 'Bbeacon',
        'seenAt': '2026-06-15T12:30:00.000Z',
      });
      expect(seen.calls, hasLength(1));
      expect(seen.calls.single.userId, 'Uauthor');
      expect(seen.calls.single.beaconId, 'Bbeacon');
      final at = seen.calls.single.at;
      expect(at.isBefore(before), isFalse);
      expect(at.isAfter(after), isFalse);
    });
  }
}

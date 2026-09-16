import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_person_shared_contexts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/use_case/person_context_case.dart';
import 'package:tentura_server/env.dart';

final class _FakePersonVisibilityPort
    implements PersonVisibilityRepositoryPort {
  List<({String beaconId, String title})> sharedContextsResult = const [];
  final calls = <({String viewerId, String peerId})>[];

  @override
  Future<List<({String beaconId, String title})>> sharedContexts({
    required String viewerId,
    required String peerId,
  }) async {
    calls.add((viewerId: viewerId, peerId: peerId));
    return sharedContextsResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakePersonVisibilityPort port;
  late QueryPersonSharedContexts query;

  setUp(() {
    port = _FakePersonVisibilityPort();
    query = QueryPersonSharedContexts(
      personContextCase: PersonContextCase(
        port,
        env: Env(environment: Environment.test),
        logger: Logger('PersonSharedContextsContractTest'),
      ),
    );
  });

  Future<Object?> resolve(String userId) => Future.value(
    query.personSharedContexts.resolve!(null, {
      kGlobalInputQueryJwt: const JwtEntity(sub: 'viewer'),
      'userId': userId,
    }),
  );

  group('schema', () {
    test('exposes personSharedContexts query', () {
      expect(
        query.all.map((f) => f.name),
        contains('personSharedContexts'),
      );
    });

    test('customTypes contains PersonSharedContext', () {
      final type = customTypes.whereType<GraphQLObjectType>().singleWhere(
        (t) => t.name == 'PersonSharedContext',
      );
      expect(
        type.fields.map((f) => f.name),
        containsAll(['beaconId', 'title']),
      );
    });
  });

  group('resolver', () {
    test('self query returns [] without calling the case', () async {
      final result = await resolve('viewer');
      expect(result, isEmpty);
      expect(port.calls, isEmpty);
    });

    test('peer query maps case rows', () async {
      port.sharedContextsResult = [(beaconId: 'B1', title: 'T1')];
      final result = await resolve('peer');
      expect(result, [
        {'beaconId': 'B1', 'title': 'T1'},
      ]);
      expect(port.calls, [(viewerId: 'viewer', peerId: 'peer')]);
    });
  });
}

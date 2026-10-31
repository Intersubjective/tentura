import 'dart:convert';
import 'dart:io' show HttpStatus, Platform;

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_invitation.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart'
    show TenturaGraphQL;
import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/consts.dart' show kInvitationDefaultTTL;
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/user_availability_repository_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/port/user_presence_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/user_availability_case.dart';
import 'package:tentura_server/domain/use_case/user_presence_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/fake_beacon_access_guard.dart';
import '../../../support/fake_user_block_repository.dart';

// The invitation TTL is a server setting (INVITATION_TTL), so the client can
// only show the right expiry if the server serves the effective value.

const _fieldName = 'invitationTtlHours';

final _processDefaultHours =
    int.tryParse(Platform.environment['INVITATION_TTL'] ?? '') ??
    kInvitationDefaultTTL;

class _UnusedInvitationPort implements InvitationRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedUserPort implements UserRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedBeaconPort implements BeaconRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedFriendshipPort implements VoteUserFriendshipLookupPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedContactPort implements UserContactRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedForwardEdgePort implements ForwardEdgeRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedPresencePort implements UserPresenceRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedAvailabilityPort implements UserAvailabilityRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

QueryInvitation _queryWith(Env env) {
  final logger = Logger('InvitationTtlQueryTest');
  final friendship = _UnusedFriendshipPort();
  return QueryInvitation(
    invitationCase: InvitationCase(
      _UnusedInvitationPort(),
      _UnusedUserPort(),
      _UnusedBeaconPort(),
      friendship,
      _UnusedContactPort(),
      FakeBeaconAccessGuard(),
      _UnusedForwardEdgePort(),
      FakeUserBlockRepository(),
      env: env,
      logger: logger,
    ),
    userPresenceCase: UserPresenceCase(
      _UnusedPresencePort(),
      env: env,
      logger: logger,
    ),
    userAvailabilityCase: UserAvailabilityCase(
      _UnusedAvailabilityPort(),
      env: env,
      logger: logger,
    ),
    voteUserFriendshipLookup: friendship,
  );
}

GraphQLObjectField<dynamic, dynamic> _ttlField(QueryInvitation query) =>
    query.all.singleWhere(
      (f) => f.name == _fieldName,
      orElse: () => throw TestFailure('Query field $_fieldName is missing'),
    );

Future<Object?> _serve(Env env) async => Future.value(
  _ttlField(_queryWith(env)).resolve!(null, {
    kGlobalInputQueryJwt: const JwtEntity(sub: 'viewer'),
  }),
);

/// POSTs [query] to the real GraphQL controller (document parsing, executor,
/// JSON encoding), with only the schema's invitation field wired to [env].
Future<Map<String, dynamic>> _post(Env env, String query) async {
  final controller = GraphqlController(
    env,
    schema: TenturaGraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', 'Query root')
          ..fields.addAll(_queryWith(env).all),
      ),
      customTypes: customTypes,
    ),
  );
  final response = await controller.handler(
    Request(
      'POST',
      Uri.parse('http://localhost/api/v2/graphql'),
      headers: {'content-type': 'application/json'},
      context: {kGlobalInputQueryJwt: const JwtEntity(sub: 'viewer')},
      body: jsonEncode({
        'operationName': 'InvitationTtl',
        'query': query,
      }),
    ),
  );
  expect(response.statusCode, HttpStatus.ok);
  return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
}

void main() {
  group('invitation TTL over the GraphQL endpoint', () {
    const query = 'query InvitationTtl { $_fieldName }';

    test('answers with the overridden TTL as a JSON integer', () async {
      final body = await _post(
        Env(
          environment: Environment.test,
          invitationTTL: const Duration(hours: 48),
        ),
        query,
      );
      expect(body['errors'], isNull);
      expect(body['data'], {_fieldName: 48});
    });

    test('answers with the process default when nothing is injected', () async {
      final body = await _post(Env(environment: Environment.test), query);
      expect(body['errors'], isNull);
      expect(body['data'], {_fieldName: _processDefaultHours});
    });

    test('answers with the injected default-sized TTL', () async {
      final body = await _post(
        Env(
          environment: Environment.test,
          invitationTTL: const Duration(hours: kInvitationDefaultTTL),
        ),
        query,
      );
      expect(body['data'], {_fieldName: kInvitationDefaultTTL});
    });
  });

  group('invitation TTL query field', () {
    test('is declared as a non-null Int', () {
      final type = _ttlField(
        _queryWith(Env(environment: Environment.test)),
      ).type;
      expect(type, isA<GraphQLNonNullableType<Object?, Object?>>());
      expect(
        (type as GraphQLNonNullableType<Object?, Object?>).ofType,
        graphQLInt,
      );
    });

    test('serves the overridden TTL in hours', () async {
      final env = Env(
        environment: Environment.test,
        invitationTTL: const Duration(hours: 48),
      );
      expect(await _serve(env), 48);
    });

    test('serves a different override, not a fixed value', () async {
      final env = Env(
        environment: Environment.test,
        invitationTTL: const Duration(hours: 5),
      );
      expect(await _serve(env), 5);
    });

    // With no injected override Env falls back to the process-wide
    // INVITATION_TTL (hours) and, when that is unset, the compiled default.
    // The expectation follows the process env so the case always runs; with
    // the variable unset it is exactly kInvitationDefaultTTL.
    test('serves the process default when nothing is injected', () async {
      final env = Env(environment: Environment.test);
      expect(await _serve(env), _processDefaultHours);
    });
  });
}

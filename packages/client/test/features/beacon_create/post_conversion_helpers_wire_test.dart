import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// gql is transitive through Ferry, as in support/gql_codegen_freshness.dart.
// ignore: depend_on_referenced_packages
import 'package:gql/ast.dart';
// ignore: depend_on_referenced_packages
import 'package:gql/language.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/data/repository/post_conversion_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';

import '../../support/test_realtime_sync.dart';

void main() {
  group('Post conversion helper mutation contract', () {
    test(
      'helperIds binds a String list variable compatible with the schema argument type and nullability',
      () {
        final schema = parseString(
          File('lib/data/gql/schema.graphql').readAsStringSync(),
        );
        final mutationRootName = schema.definitions
            .whereType<SchemaDefinitionNode>()
            .single
            .operationTypes
            .singleWhere((type) => type.operation == OperationType.mutation)
            .type
            .name
            .value;
        final root = schema.definitions
            .whereType<ObjectTypeDefinitionNode>()
            .singleWhere((type) => type.name.value == mutationRootName);
        final field = root.fields.singleWhere(
          (field) => field.name.value == 'beaconConvertToRequest',
        );
        final helperArguments = field.args.where(
          (arg) => arg.name.value == 'helperIds',
        );
        expect(
          helperArguments,
          hasLength(1),
          reason: 'The conversion schema must declare helperIds',
        );
        final argument = helperArguments.single;
        expect(argument.type, isA<ListTypeNode>());
        final elementType = (argument.type as ListTypeNode).type;
        expect(elementType, isA<NamedTypeNode>());
        expect((elementType as NamedTypeNode).name.value, 'String');

        final document = parseString(
          File(
            'lib/features/beacon/data/gql/beacon_convert_to_request.graphql',
          ).readAsStringSync(),
        );
        final operation = document.definitions
            .whereType<OperationDefinitionNode>()
            .single;
        expect(operation.type, OperationType.mutation);
        expect(operation.name!.value, 'BeaconConvertToRequest');
        final conversion = operation.selectionSet.selections
            .whereType<FieldNode>()
            .singleWhere(
              (field) => field.name.value == 'beaconConvertToRequest',
            );
        final bindings = conversion.arguments.where(
          (arg) => arg.name.value == 'helperIds',
        );
        expect(
          bindings,
          hasLength(1),
          reason: 'The mutation must bind the helperIds argument',
        );
        expect(bindings.single.value, isA<VariableNode>());
        final variableName = (bindings.single.value as VariableNode).name.value;
        expect(variableName, 'helperIds');
        final variable = operation.variableDefinitions.singleWhere(
          (variable) => variable.variable.name.value == variableName,
        );
        final defaultValue = variable.defaultValue?.value;
        final hasNonNullVariableDefault =
            defaultValue != null && defaultValue is! NullValueNode;
        expect(
          _compatibleVariableType(
            variable.type,
            argument.type,
            allowNullableAtRoot:
                hasNonNullVariableDefault || argument.defaultValue != null,
          ),
          isTrue,
          reason:
              'helperIds must agree on list/scalar type and element/list nullability; '
              'a nullable variable cannot supply a non-null schema type without a default',
        );
      },
    );

    test(
      'conversion sends exactly the selected member ids as helperIds',
      () async {
        final variables = await _conversionVariables(['Ureader', 'Usecond']);
        expect(variables['id'], 'Bpostconvert1');
        expect(variables['helperIds'], unorderedEquals(['Ureader', 'Usecond']));
      },
    );

    test(
      'conversion with no selected members sends an explicit empty helperIds list',
      () async {
        final variables = await _conversionVariables(const []);
        expect(variables, contains('helperIds'));
        expect(variables['helperIds'], isEmpty);
      },
    );
  });
}

/// Runs the real repository and Ferry serialization over an HTTP test client.
/// All responses are canned; no server, database, or live network is used.
Future<Map<String, dynamic>> _conversionVariables(
  List<String> helperIds,
) async {
  final sent = <Map<String, dynamic>>[];
  await http.runWithClient(
    () async {
      final remote = RemoteApiService(
        const Env(),
        const WebSocketClientRealtimeSocketFactory(),
      );
      final sync = buildTestRealtimeSync();
      try {
        await remote.setSessionAuth();
        final repository = PostConversionRepository(
          remote,
          BeaconRepository(remote, sync.port),
          BeaconThreadsRepository(remote, sync.port),
        );
        final arguments = <Symbol, dynamic>{
          #beaconId: 'Bpostconvert1',
          #title: 'Need a ladder',
          #description: 'I can pick it up on Saturday.',
          #needs: <String>{},
          #primaryNeedSlug: null,
          #startAt: null,
          #endAt: null,
          #isDiscoverable: true,
          #helperIds: helperIds,
        };
        try {
          await (Function.apply(
                repository.convertToRequest,
                const [],
                arguments,
              )
              as Future<void>);
        } on NoSuchMethodError {
          fail('PostConversionRepository must accept selected helperIds');
        }
      } finally {
        await remote.close();
        await sync.port.dispose();
      }
    },
    () => MockClient((request) async {
      if (request.url.path.endsWith('/session/access-token')) {
        return http.Response(
          jsonEncode({
            'subject': 'Uauthor000001',
            'access_token': 'test-token',
            'expires_in': 3600,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['operationName'], 'BeaconConvertToRequest');
      sent.add((body['variables'] as Map).cast<String, dynamic>());
      return http.Response(
        jsonEncode({
          'data': {
            'beaconConvertToRequest': {
              '__typename': 'v2_Beacon',
              'id': 'Bpostconvert1',
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  expect(sent, hasLength(1));
  return sent.single;
}

// GraphQL permits a non-null variable at a nullable argument location. The
// reverse requires a variable/argument default at the outermost level; list
// element nullability must be compatible independently of those defaults.
bool _compatibleVariableType(
  TypeNode variable,
  TypeNode argument, {
  bool allowNullableAtRoot = false,
}) {
  if (argument.isNonNull && !variable.isNonNull && !allowNullableAtRoot) {
    return false;
  }
  if (variable is ListTypeNode && argument is ListTypeNode) {
    return _compatibleVariableType(variable.type, argument.type);
  }
  if (variable is NamedTypeNode && argument is NamedTypeNode) {
    return variable.name.value == argument.name.value;
  }
  return false;
}

import 'dart:convert';

import 'package:ferry/ferry.dart'
    show DataSource, FetchPolicy, JsonOperationRequest;
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart' show FieldNode, OperationDefinitionNode;
import 'package:gql/language.dart' show parseString;
import 'package:gql_exec/gql_exec.dart' show Operation;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tentura/data/service/remote_api_client/build_client.dart';
import 'package:tentura/data/service/remote_api_service.dart' show ErrorHandler;
import 'package:tentura/domain/exception/generic_exception.dart';

const _phantomId = 'PH0123456789ab';
const _userId = 'Upeer00000001';
const _v2Path = '/api/v2/graphql';

void main() {
  group('phantom mutation transport', () {
    for (final command in _commands) {
      test(command.behavior, () async {
        final paths = <String>[];
        final bodies = <Map<String, dynamic>>[];
        final isUnmerge = command.field == 'phantomUnmerge';
        final errorMessage = isUnmerge
            ? 'Remove someone not on Tentura yet first.'
            : 'The command could not be completed';
        var answerWithError = false;
        final client = await buildClient(
          params: (
            apiEndpointUrl: 'https://example.test/api/v1/graphql',
            apiEndpointUrlV2: 'https://example.test$_v2Path',
            userAgent: 'test',
            requestTimeout: const Duration(seconds: 1),
          ),
          getToken: () async => 'test-token',
          httpClient: MockClient((request) async {
            paths.add(request.url.path);
            bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            final payload = answerWithError
                ? {
                    'errors': [
                      {
                        'message': errorMessage,
                        if (isUnmerge)
                          'extensions': {
                            'code': '1006',
                            'reason': 'phantom_cap_reached',
                          },
                      },
                    ],
                  }
                : {
                    'data': {command.field: command.result},
                  };
            return http.Response(
              jsonEncode(payload),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);

        Future<Object?> send(Map<String, dynamic> variables) async {
          final reply = await client
              .request(
                JsonOperationRequest(
                  operation: Operation(
                    document: parseString(command.document),
                    operationName: command.operationName,
                  ),
                  vars: variables,
                  fetchPolicy: FetchPolicy.NoCache,
                ),
              )
              .firstWhere((event) => event.dataSource == DataSource.Link)
              .timeout(const Duration(seconds: 2));
          return reply.dataOrThrow(label: command.operationName)[command.field];
        }

        for (final variables in command.inputs) {
          expect(await send(variables), command.result);
        }

        answerWithError = true;
        await expectLater(
          send(command.inputs.first),
          throwsA(
            isA<RemoteApiException>().having(
              (error) => error.message,
              'server message',
              errorMessage,
            ),
          ),
        );

        final expectedVariables = [...command.inputs, command.inputs.first];
        expect(
          bodies.map((body) => body['operationName']),
          everyElement(command.operationName),
        );
        expect(bodies.map((body) => body['variables']), expectedVariables);
        for (final body in bodies) {
          final operation = parseString(
            body['query'] as String,
          ).definitions.whereType<OperationDefinitionNode>().single;
          final fields = operation.selectionSet.selections
              .whereType<FieldNode>()
              .map((field) => field.name.value)
              .where((name) => name != '__typename');
          expect(fields, [command.field]);
        }
        expect(paths, List.filled(expectedVariables.length, _v2Path));
      });
    }
  });
}

final class _Command {
  const _Command({
    required this.behavior,
    required this.operationName,
    required this.field,
    required this.document,
    required this.inputs,
    required this.result,
  });

  final String behavior;
  final String operationName;
  final String field;
  final String document;
  final List<Map<String, dynamic>> inputs;
  final Object result;
}

const _commands = [
  _Command(
    behavior: 'creating a phantom sends optional appearance and position to V2',
    operationName: 'PhantomCreate',
    field: 'phantomCreate',
    document: r'''
      mutation PhantomCreate($name: String!, $emoji: String, $position: v2_ConstellationAnchorPositionInput) {
        phantomCreate(name: $name, emoji: $emoji, position: $position)
      }
    ''',
    inputs: [
      {
        'name': 'Anna',
        'emoji': '🌿',
        'position': {
          'xUnits': 1.5,
          'yUnits': -2.25,
          'coordinateSpaceVersion': 1,
        },
      },
      {'name': 'Anna', 'emoji': null},
    ],
    result: _phantomId,
  ),
  _Command(
    behavior: 'updating a phantom sends the changed name and emoji to V2',
    operationName: 'PhantomUpdate',
    field: 'phantomUpdate',
    document: r'''
      mutation PhantomUpdate($id: String!, $name: String!, $emoji: String) {
        phantomUpdate(id: $id, name: $name, emoji: $emoji)
      }
    ''',
    inputs: [
      {'id': _phantomId, 'name': 'Anna K.', 'emoji': null},
    ],
    result: true,
  ),
  _Command(
    behavior: 'deleting a phantom addresses the selected id on V2',
    operationName: 'PhantomDelete',
    field: 'phantomDelete',
    document: r'''
      mutation PhantomDelete($id: String!) {
        phantomDelete(id: $id)
      }
    ''',
    inputs: [
      {'id': _phantomId},
    ],
    result: true,
  ),
  _Command(
    behavior: 'ensuring an invite gets the existing link from V2',
    operationName: 'PhantomInviteEnsure',
    field: 'phantomInviteEnsure',
    document: r'''
      mutation PhantomInviteEnsure($id: String!) {
        phantomInviteEnsure(id: $id)
      }
    ''',
    inputs: [
      {'id': _phantomId},
    ],
    result: 'I123456789abc',
  ),
  _Command(
    behavior: 'rotating an invite gets a replacement link from V2',
    operationName: 'PhantomInviteRotate',
    field: 'phantomInviteRotate',
    document: r'''
      mutation PhantomInviteRotate($id: String!) {
        phantomInviteRotate(id: $id)
      }
    ''',
    inputs: [
      {'id': _phantomId},
    ],
    result: 'Icba987654321',
  ),
  _Command(
    behavior: 'linking a phantom sends its id and the selected account to V2',
    operationName: 'PhantomLink',
    field: 'phantomLink',
    document: r'''
      mutation PhantomLink($phantomId: String!, $userId: String!) {
        phantomLink(phantomId: $phantomId, userId: $userId)
      }
    ''',
    inputs: [
      {'phantomId': _phantomId, 'userId': _userId},
    ],
    result: true,
  ),
  _Command(
    behavior: 'undoing a merge addresses the merged phantom on V2',
    operationName: 'PhantomUnmerge',
    field: 'phantomUnmerge',
    document: r'''
      mutation PhantomUnmerge($phantomId: String!) {
        phantomUnmerge(phantomId: $phantomId)
      }
    ''',
    inputs: [
      {'phantomId': _phantomId},
    ],
    result: true,
  ),
  _Command(
    behavior: 'dismissing a link hint sends both ids to V2',
    operationName: 'PhantomHintDismiss',
    field: 'phantomHintDismiss',
    document: r'''
      mutation PhantomHintDismiss($phantomId: String!, $userId: String!) {
        phantomHintDismiss(phantomId: $phantomId, userId: $userId)
      }
    ''',
    inputs: [
      {'phantomId': _phantomId, 'userId': _userId},
    ],
    result: true,
  ),
];

// The repository is absent at the red baseline. The test entry point binds
// its real constructor when available, and the calls below go to that object.
// ignore_for_file: avoid_dynamic_calls

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/remote_wire_harness.dart';

const _phantomId = 'PH0123456789ab';
const _userId = 'Upeer00000001';
const _name = 'Anna';
const _emoji = '🌿';
const _position = ConstellationAnchorPosition(
  xUnits: 1.5,
  yUnits: -2.25,
  coordinateSpaceVersion: 1,
);
const _idVariables = {'id': _phantomId};
const _twoTargetVariables = {'phantomId': _phantomId, 'userId': _userId};

typedef PhantomRepositoryFactory = Object? Function(RemoteApiService remote);

void registerPhantomRepositoryWireTests(PhantomRepositoryFactory create) {
  final commands = [
    _Command(
      behavior:
          'create forwards the name, emoji and position and returns the id',
      operation: 'PhantomCreate',
      field: 'phantomCreate',
      variables: const {
        'name': _name,
        'emoji': _emoji,
        'position': {
          'xUnits': 1.5,
          'yUnits': -2.25,
          'coordinateSpaceVersion': 1,
        },
      },
      result: 'PHfedcba987654',
      call: (repo) async => await repo.create(
        name: _name,
        emoji: _emoji,
        position: _position,
      ),
    ),
    _Command(
      behavior: 'update sends the selected id and the edited name and emoji',
      operation: 'PhantomUpdate',
      field: 'phantomUpdate',
      variables: const {'id': _phantomId, 'name': 'Anna K.', 'emoji': '🌻'},
      result: true,
      call: (repo) async => await repo.update(
        id: _phantomId,
        name: 'Anna K.',
        emoji: '🌻',
      ),
    ),
    _Command(
      behavior: 'delete sends the id of the selected phantom',
      operation: 'PhantomDelete',
      field: 'phantomDelete',
      variables: _idVariables,
      result: true,
      call: (repo) async => await repo.delete(id: _phantomId),
    ),
    _Command(
      behavior:
          'ensure invite sends the phantom id and returns the existing link',
      operation: 'PhantomInviteEnsure',
      field: 'phantomInviteEnsure',
      variables: _idVariables,
      result: 'I123456789abc',
      call: (repo) async => await repo.inviteEnsure(id: _phantomId),
    ),
    _Command(
      behavior:
          'rotate invite sends the phantom id and returns the replacement link',
      operation: 'PhantomInviteRotate',
      field: 'phantomInviteRotate',
      variables: _idVariables,
      result: 'Icba987654321',
      call: (repo) async => await repo.inviteRotate(id: _phantomId),
    ),
    _Command(
      behavior: 'link sends the selected phantom and account ids',
      operation: 'PhantomLink',
      field: 'phantomLink',
      variables: _twoTargetVariables,
      result: true,
      call: (repo) async =>
          await repo.link(phantomId: _phantomId, userId: _userId),
    ),
    _Command(
      behavior: 'unmerge sends the id of the merged phantom',
      operation: 'PhantomUnmerge',
      field: 'phantomUnmerge',
      variables: const {'phantomId': _phantomId},
      result: true,
      call: (repo) async => await repo.unmerge(phantomId: _phantomId),
    ),
    _Command(
      behavior: 'dismiss hint sends both ids of the link suggestion',
      operation: 'PhantomHintDismiss',
      field: 'phantomHintDismiss',
      variables: _twoTargetVariables,
      result: true,
      call: (repo) async => await repo.hintDismiss(
        phantomId: _phantomId,
        userId: _userId,
      ),
    ),
  ];

  group('PhantomRepository V2 commands', () {
    for (final command in commands) {
      test(command.behavior, () => _exercise(create, command));
    }

    test('create accepts a name alone and returns the server id', () {
      return _exercise(
        create,
        _Command(
          behavior: 'create without an emoji or position',
          operation: 'PhantomCreate',
          field: 'phantomCreate',
          variables: const {'name': _name},
          result: 'PHab0987654321',
          call: (repo) async => await repo.create(name: _name),
          nullableVariables: const {'emoji', 'position'},
        ),
      );
    });

    for (final command in commands) {
      test('${command.operation} fails when GraphQL rejects it', () {
        return _exercise(create, command, graphQLError: true);
      });
    }

    for (final command in commands.where((command) => command.result is bool)) {
      test('${command.operation} fails when the server returns false', () {
        return _exercise(create, command, rejected: true);
      });
    }
  });
}

Future<void> _exercise(
  PhantomRepositoryFactory create,
  _Command command, {
  bool graphQLError = false,
  bool rejected = false,
}) async {
  final sent = <WireSent>[];
  final paths = <String>[];
  final isUnmerge = command.field == 'phantomUnmerge';

  await withRemoteWire(
    {
      command.operation: {command.field: rejected ? false : command.result},
    },
    sent,
    (remote) async {
      final repository = create(remote);
      if (repository == null) {
        fail(
          'The client must provide PhantomRepository to call ${command.field}',
        );
      }

      final result = command
          .call(repository)
          .timeout(const Duration(seconds: 2));
      if (graphQLError || rejected) {
        await expectLater(
          result,
          throwsA(allOf(isA<Exception>(), isNot(isA<TimeoutException>()))),
        );
      } else if (command.result is String) {
        expect(await result, command.result);
      } else {
        // Boolean success may be represented as true or as Future<void>.
        expect(await result, anyOf(isNull, isTrue));
      }

      expect(sent, hasLength(1));
      final call = sent.single;
      expect(call.operationName, command.operation);
      final variables = Map.of(call.variables)
        ..removeWhere(
          (key, value) =>
              command.nullableVariables.contains(key) && value == null,
        );
      expect(variables, command.variables);
      expect(paths, ['/api/v2/graphql']);
    },
    errors: {
      if (graphQLError)
        command.operation: {
          'message': isUnmerge
              ? 'Remove someone not on Tentura yet first.'
              : 'The command could not be completed',
          if (isUnmerge)
            'extensions': {'code': '1006', 'reason': 'phantom_cap_reached'},
        },
    },
    requestPaths: paths,
  );
}

final class _Command {
  const _Command({
    required this.behavior,
    required this.operation,
    required this.field,
    required this.variables,
    required this.result,
    required this.call,
    this.nullableVariables = const {},
  });

  final String behavior;
  final String operation;
  final String field;
  final Map<String, Object?> variables;
  final Object result;
  final Future<Object?> Function(dynamic repository) call;
  final Set<String> nullableVariables;
}

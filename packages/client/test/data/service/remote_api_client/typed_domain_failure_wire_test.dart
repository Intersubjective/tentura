import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/exception/baton_exceptions.dart';
import 'package:tentura/features/constellation/data/repository/constellation_anchor_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/exception.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../../support/test_realtime_sync.dart';

// Exercise typed catches at the use-case boundary with real repositories,
// session setup, HTTP transport, Ferry error links and failure classification.
final class _CatchingCase extends UseCaseBase {
  _CatchingCase(this.batons, this.anchors)
    : super(env: const Env(), logger: Logger('TypedFailureWireTest'));

  final BeaconThreadsRepository batons;
  final ConstellationAnchorRepositoryPort anchors;

  Future<BatonException?> createBaton() async {
    try {
      await batons.batonCreate(
        beaconId: 'Brequest',
        text: 'Who can help?',
        candidates: [(userId: 'Ucandidate', tier: 1)],
      );
    } on BatonException catch (error) {
      return error;
    }
    return null;
  }

  Future<ConstellationException?> placeAnchor() async {
    try {
      await anchors.apply(
        ops: [
          ConstellationAnchorApplyOp(
            clientOpId: 'op-place',
            kind: ConstellationAnchorOpKind.upsert,
            target: ConstellationAnchorTarget.person('Upeer'),
            position: const ConstellationAnchorPosition(
              xUnits: 1.5,
              yUnits: 2.5,
              coordinateSpaceVersion: 1,
            ),
          ),
        ],
        params: ConstellationFieldMembershipFilters.defaults,
      );
    } on ConstellationException catch (error) {
      return error;
    }
    return null;
  }
}

void main() {
  for (final family in ['baton', 'constellation']) {
    test('$family wire error reaches the typed use-case catch', () async {
      final operations = <String>[];
      final paths = <String>[];
      final code = family == 'baton'
          ? BatonNotAuthorException.codeNumber
          : ConstellationInvalidCoordinatesException.codeNumber;
      final server = MockClient((request) async {
        if (request.url.path.endsWith('/session/access-token')) {
          return http.Response(
            jsonEncode({
              'subject': 'Uviewer000001',
              'access_token': 'test-token',
              'expires_in': 3600,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        operations.add(body['operationName'] as String);
        paths.add(request.url.path);
        return http.Response(
          jsonEncode({
            'errors': [
              {
                'message': 'Typed domain failure',
                'extensions': {'code': code},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await http.runWithClient(() async {
        final remote = RemoteApiService(
          const Env(),
          const WebSocketClientRealtimeSocketFactory(),
        );
        final realtime = TestRealtimeSyncPort();
        final batons = BeaconThreadsRepository(remote, realtime);
        final useCase = _CatchingCase(
          batons,
          ConstellationAnchorRepository(remote),
        );
        try {
          await remote.setSessionAuth();
          if (family == 'baton') {
            expect(await useCase.createBaton(), isA<BatonNotAuthorException>());
            expect(operations, ['RoomBatonCreate']);
          } else {
            expect(
              await useCase.placeAnchor(),
              isA<ConstellationInvalidCoordinatesException>(),
            );
            expect(operations, ['ConstellationAnchorsApply']);
          }
          expect(paths, [
            family == 'baton' ? kPathGraphQLEndpoint : kPathGraphQLEndpointV2,
          ]);
        } finally {
          await batons.dispose();
          await realtime.dispose();
          await remote.close();
        }
      }, () => server);
    });
  }
}

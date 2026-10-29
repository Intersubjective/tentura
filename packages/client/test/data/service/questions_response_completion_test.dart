import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/features/beacon_lobby/data/gql/_g/beacon_lobby.req.gql.dart';

void main() {
  final request = GBeaconLobbyReq((b) => b..vars.beaconId = 'B1');

  test(
    'Questions response completion without a network answer is typed',
    () async {
      await expectLater(
        const Stream<OperationResponse<Object, Object>>.empty()
            .firstLinkResponse(label: 'BeaconLobby'),
        throwsA(isA<GraphQLNoDataException>()),
      );
    },
  );

  test('Questions cache-only completion is not a network answer', () async {
    final cached = OperationResponse<Object, Object>(
      operationRequest: request,
      dataSource: DataSource.Cache,
    );
    await expectLater(
      Stream.value(cached).firstLinkResponse(label: 'BeaconLobby'),
      throwsA(isA<GraphQLNoDataException>()),
    );
  });
  test('Questions accepts a network answer after a cache response', () async {
    final cached = OperationResponse<Object, Object>(
      operationRequest: request,
      dataSource: DataSource.Cache,
    );
    final network = OperationResponse<Object, Object>(
      operationRequest: request,
      dataSource: DataSource.Link,
    );
    expect(
      await Stream.fromIterable([
        cached,
        network,
      ]).firstLinkResponse(label: 'BeaconLobby'),
      same(network),
    );
  });

  test('Questions preserves an upstream failure', () async {
    final failure = Exception('transport failed');
    await expectLater(
      Stream<OperationResponse<Object, Object>>.error(
        failure,
      ).firstLinkResponse(label: 'BeaconLobby'),
      throwsA(same(failure)),
    );
  });
}

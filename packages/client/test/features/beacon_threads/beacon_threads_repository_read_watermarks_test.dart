// tentura-fpi landing gate acceptance (chat read receipts / room_seen_peer)

import 'package:ferry/ferry.dart'
    show
        Client,
        FetchPolicy,
        Link,
        NextLink,
        OperationRequest,
        OperationResponse,
        OperationType;
import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' show Request, Response;

import 'package:tentura/data/service/remote_api_client/remote_api_client_web.dart';
import 'package:tentura/domain/entity/room_read_watermark.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';

import '../../support/test_realtime_sync.dart';

class _FakeLink extends Link {
  _FakeLink(this.response);

  final Response response;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) =>
      Stream.value(response);
}

final class _StubRemoteApiClient extends RemoteApiClient {
  _StubRemoteApiClient(this._client)
    : super(
        apiEndpointUrl: 'http://test/graphql',
        apiEndpointUrlV2: 'http://test/api/v2/graphql',
        authJwtExpiresIn: const Duration(hours: 1),
        requestTimeout: const Duration(minutes: 1),
        userAgent: 'test',
      );

  final Client _client;

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) =>
      _client.request(request);
}

void main() {
  test(
    'fetchMainRoomReadWatermarks maps Ferry rows to RoomReadWatermark entities',
    () async {
      const beaconId = 'Bbeacon0000001';
      const userA = 'Uuseraaaaaaaa01';
      const userB = 'Uuserbbbbbbbb02';

      final client = Client(
        link: _FakeLink(
          const Response(
            data: {
              '__typename': 'query_root',
              'BeaconRoomReadWatermarks': [
                {
                  '__typename': 'v2_v2_RoomReadWatermark',
                  'userId': userA,
                  'lastSeenAt': '2026-08-14T10:00:00.000Z',
                  'userTitle': 'Alice',
                  'userHasPicture': true,
                  'userImageId': 'img-a',
                  'userBlurHash': 'hash-a',
                  'userPicHeight': 100,
                  'userPicWidth': 200,
                },
                {
                  '__typename': 'v2_v2_RoomReadWatermark',
                  'userId': userB,
                  'lastSeenAt': '2026-08-15T13:30:00.000+03:00',
                  'userTitle': 'Bob',
                  'userHasPicture': false,
                  'userImageId': '',
                  'userBlurHash': '',
                  'userPicHeight': 0,
                  'userPicWidth': 0,
                },
              ],
            },
            response: {},
          ),
        ),
        defaultFetchPolicies: const {
          OperationType.query: FetchPolicy.NoCache,
        },
      );

      final realtime = buildTestRealtimeSync();
      final repo = BeaconThreadsRepository(
        _StubRemoteApiClient(client),
        realtime.port,
      );
      addTearDown(realtime.port.dispose);

      final rows = await repo.fetchMainRoomReadWatermarks(beaconId);

      expect(rows, hasLength(2));

      final alice = rows[0];
      expect(alice.userId, userA);
      expect(alice.lastSeenAt, DateTime.utc(2026, 8, 14, 10));
      expect(alice.lastSeenAt.isUtc, isTrue);
      expect(alice.userTitle, 'Alice');
      expect(alice.userHasPicture, isTrue);
      expect(alice.userImageId, 'img-a');
      expect(alice.userBlurHash, 'hash-a');
      expect(alice.userPicHeight, 100);
      expect(alice.userPicWidth, 200);

      final bob = rows[1];
      expect(bob.userId, userB);
      expect(bob.lastSeenAt, DateTime.utc(2026, 8, 15, 10, 30));
      expect(bob.lastSeenAt.isUtc, isTrue);
      expect(bob.userTitle, 'Bob');
      expect(bob.userHasPicture, isFalse);
      expect(bob.userImageId, isEmpty);
      expect(bob.userBlurHash, isEmpty);
      expect(bob.userPicHeight, 0);
      expect(bob.userPicWidth, 0);
    },
  );
}

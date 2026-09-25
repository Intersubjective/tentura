// Issue #178 part 2: the real `CoordinationRepository` (not the fakes the
// cubit/widget tests use), over the real `RemoteApiService` and Ferry link
// chain, must request and map `authorSeenAt` from `helpOffersWithCoordination`
// and send `MarkBeaconPeopleSeen` to Tentura V2 with the request id and
// read-through time. Only the HTTP transport is faked (via
// `http.runWithClient`), so the repository constructor stays as it is.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/service/remote_api_client/realtime_socket.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_view/data/repository/coordination_repository.dart';

const _beaconId = 'Bauthorseen01';

Map<String, dynamic> _offerJson({
  required String userId,
  String? authorSeenAt,
}) => {
  '__typename': 'HelpOfferWithCoordinationRow',
  'beaconId': _beaconId,
  'userId': userId,
  'message': 'I can help',
  'helpType': null,
  'roleLabel': null,
  'status': 0,
  'withdrawReason': null,
  'createdAt': '2026-06-15T12:00:00.000Z',
  'updatedAt': '2026-06-15T12:00:00.000Z',
  'responseType': null,
  'responseUpdatedAt': null,
  'responseAuthorUserId': null,
  'roomAccess': null,
  'admissionAction': null,
  'lastDeclineReason': null,
  'lastRemoveReason': null,
  'offerKind': 0,
  'stakeState': 0,
  'isDirectAuthorForward': false,
  'authorSeenAt': authorSeenAt,
  'user': {
    '__typename': 'User',
    'id': userId,
    'displayName': userId,
    'description': '',
    'my_vote': null,
    'trusts_viewer': false,
    'is_mutual_friend': false,
    'image': null,
    'user_presence': null,
    'user_availability': null,
  },
};

/// A GraphQL request as it went over the wire.
typedef _SentOperation = ({
  Uri url,
  String operationName,
  String query,
  Map<String, dynamic> variables,
});

/// Runs [body] against a real, session-authenticated [RemoteApiService]
/// whose HTTP transport answers GraphQL operations from [responses] (keyed by
/// operation name) and records them in [sent].
Future<void> _withRemote(
  Map<String, Map<String, dynamic>> responses,
  List<_SentOperation> sent,
  Future<void> Function(RemoteApiService remote) body,
) => http.runWithClient(
  () async {
    final remote = RemoteApiService(
      const Env(),
      const WebSocketClientRealtimeSocketFactory(),
    );
    try {
      await remote.setSessionAuth();
      await body(remote);
    } finally {
      await remote.close();
    }
  },
  () => MockClient((request) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return http.Response(
        jsonEncode({
          'subject': 'Uofferer00001',
          'access_token': 'test-token',
          'expires_in': 3600,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    final json = jsonDecode(request.body) as Map<String, dynamic>;
    final name = json['operationName'] as String;
    sent.add((
      url: request.url,
      operationName: name,
      query: json['query'] as String,
      variables: (json['variables'] as Map).cast<String, dynamic>(),
    ));
    final data = responses[name];
    if (data == null) {
      return http.Response('{"errors":[{"message":"unexpected $name"}]}', 200);
    }
    return http.Response(
      jsonEncode({'data': data}),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

void main() {
  test('fetchHelpOffersWithCoordination requests and maps authorSeenAt '
      'per row', () async {
    final sent = <_SentOperation>[];
    await _withRemote(
      {
        'HelpOffersWithCoordination': {
          '__typename': 'query_root',
          'helpOffersWithCoordination': [
            _offerJson(
              userId: 'Uofferer00001',
              authorSeenAt: '2026-06-15T12:05:00.000Z',
            ),
            _offerJson(userId: 'Uofferer00002'),
          ],
        },
      },
      sent,
      (remote) async {
        final rows = await CoordinationRepository(
          remote,
        ).fetchHelpOffersWithCoordination(beaconId: _beaconId);

        expect(rows, hasLength(2));
        final seen = rows.firstWhere((r) => r.userId == 'Uofferer00001');
        final unseen = rows.firstWhere((r) => r.userId == 'Uofferer00002');
        expect(seen.authorSeenAt, DateTime.utc(2026, 6, 15, 12, 5));
        expect(seen.authorSeenAt!.isUtc, isTrue);
        expect(unseen.authorSeenAt, isNull);
      },
    );

    expect(sent.single.operationName, 'HelpOffersWithCoordination');
    expect(sent.single.query, contains(RegExp(r'\bauthorSeenAt\b')));
  });

  test(
    'markBeaconPeopleSeen sends MarkBeaconPeopleSeen to V2 with beaconId and '
    'readThroughAt, and returns the server seenAt',
    () async {
      final sent = <_SentOperation>[];
      late DateTime seenAt;
      await _withRemote(
        {
          'MarkBeaconPeopleSeen': {
            '__typename': 'mutation_root',
            'MarkBeaconPeopleSeen': {
              '__typename': 'BeaconPeopleSeenResult',
              'beaconId': _beaconId,
              'seenAt': '2026-06-15T12:10:00.000Z',
            },
          },
        },
        sent,
        (remote) async {
          seenAt = await CoordinationRepository(remote).markBeaconPeopleSeen(
            beaconId: _beaconId,
            readThroughAt: DateTime.utc(2026, 6, 15, 12, 9),
          );
        },
      );

      expect(sent, hasLength(1));
      final op = sent.single;
      expect(op.operationName, 'MarkBeaconPeopleSeen');
      expect(op.url.path, '/api/v2/graphql');
      expect(op.variables['beaconId'], _beaconId);
      expect(
        DateTime.parse(op.variables['readThroughAt'] as String),
        DateTime.utc(2026, 6, 15, 12, 9),
      );
      expect(seenAt, DateTime.utc(2026, 6, 15, 12, 10));
      expect(seenAt.isUtc, isTrue);
    },
  );
}

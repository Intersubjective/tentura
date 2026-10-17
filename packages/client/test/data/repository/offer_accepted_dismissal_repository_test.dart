// B077b: the «Your help was accepted» dismissals live on the server per
// account. The real repository, over the real `RemoteApiService` and Ferry
// link chain, reads them with `OfferAcceptedDismissals` and records one with
// `DismissOfferAccepted`, both sent to Tentura V2. Only the HTTP transport is
// faked (via `http.runWithClient`).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/data/repository/offer_accepted_dismissal_repository.dart';
import 'package:tentura/domain/attention/offer_accepted_dismissals.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';

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
  Future<void> Function(RemoteApiService remote) body, {
  int? failStatus,
}) => http.runWithClient(
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
          'subject': 'Uhelper00001',
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
    if (failStatus != null) {
      return http.Response('Service Unavailable', failStatus);
    }
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
  test("load reads the account's dismissals from V2", () async {
    final sent = <_SentOperation>[];
    late Set<String> loaded;
    await _withRemote(
      {
        'OfferAcceptedDismissals': {
          '__typename': 'query_root',
          'offerAcceptedDismissals': {
            '__typename': 'OfferAcceptedDismissals',
            'userId': 'Uhelper00001',
            'beaconIds': ['B1', 'B2'],
          },
        },
      },
      sent,
      (remote) async {
        loaded = await OfferAcceptedDismissalRepository(
          remote,
        ).load(viewerId: 'Uhelper00001');
      },
    );

    expect(sent.single.operationName, 'OfferAcceptedDismissals');
    expect(sent.single.url.path, '/api/v2/graphql');
    expect(loaded, {'B1', 'B2'});
  });

  test("another account's answer (account switched) is not taken", () async {
    Object? error;
    await _withRemote(
      {
        'OfferAcceptedDismissals': {
          '__typename': 'query_root',
          'offerAcceptedDismissals': {
            '__typename': 'OfferAcceptedDismissals',
            'userId': 'Usomeone0001',
            'beaconIds': ['B1'],
          },
        },
      },
      <_SentOperation>[],
      (remote) async {
        try {
          await OfferAcceptedDismissalRepository(
            remote,
          ).load(viewerId: 'Uhelper00001');
        } on Object catch (e) {
          error = e;
        }
      },
    );
    expect(error, isNotNull);
  });

  test('dismiss records it on V2 and returns what the server holds', () async {
    final sent = <_SentOperation>[];
    late Set<String> after;
    await _withRemote(
      {
        'DismissOfferAccepted': {
          '__typename': 'mutation_root',
          'DismissOfferAccepted': {
            '__typename': 'OfferAcceptedDismissals',
            'userId': 'Uhelper00001',
            'beaconIds': ['B1', 'B3'],
          },
        },
      },
      sent,
      (remote) async {
        after = await OfferAcceptedDismissalRepository(
          remote,
        ).dismiss(viewerId: 'Uhelper00001', beaconId: 'B3');
      },
    );

    final op = sent.single;
    expect(op.operationName, 'DismissOfferAccepted');
    expect(op.url.path, '/api/v2/graphql');
    expect(op.variables['beaconId'], 'B3');
    expect(after, {'B1', 'B3'});
  });

  // #537 review: a refusal the server answered is told apart from a network
  // failure, so the store drops it instead of sending it on every build.
  test('a dismissal the server refuses is reported as refused', () async {
    final sent = <_SentOperation>[];
    await _withRemote({}, sent, (remote) async {
      await expectLater(
        OfferAcceptedDismissalRepository(
          remote,
        ).dismiss(viewerId: 'Uhelper00001', beaconId: 'B3'),
        throwsA(isA<OfferAcceptedDismissalRefusedException>()),
      );
    });
    expect(sent.single.operationName, 'DismissOfferAccepted');
  });

  test('a server outage is not reported as a refusal', () async {
    final sent = <_SentOperation>[];
    await _withRemote({}, sent, failStatus: 503, (remote) async {
      await expectLater(
        OfferAcceptedDismissalRepository(
          remote,
        ).dismiss(viewerId: 'Uhelper00001', beaconId: 'B3'),
        throwsA(isNot(isA<OfferAcceptedDismissalRefusedException>())),
      );
    });
  });

  test('ENV=test has a stub for the port, like every repository', () async {
    final OfferAcceptedDismissalPort stub =
        OfferAcceptedDismissalRepositoryMock();
    expect(await stub.load(viewerId: 'Uhelper00001'), isEmpty);
    expect(
      await stub.dismiss(viewerId: 'Uhelper00001', beaconId: 'B3'),
      {'B3'},
    );
  });
}

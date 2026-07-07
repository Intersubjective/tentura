import 'package:ferry/ferry.dart'
    show Client, DataSource, FetchPolicy, Link, NextLink, OperationType;
import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' show Request, Response;

import 'package:tentura/data/service/remote_api_service.dart'
    show ErrorHandler;
import 'package:tentura/features/evaluation/data/gql/_g/beacon_close.req.gql.dart';

/// Regression guard for the "Wrapping up" hang (issue #74).
///
/// The V2 server's `beaconClose` resolver returns only `{id, status, closesAt}`
/// and silently drops any other selected fields. If the client selects fields
/// the server never returns (previously `requiresReviewWindow` /
/// `branchMismatch`, both non-nullable in the generated data class), Ferry
/// cannot build the response, `data` is null / parsing throws, and the whole
/// close/wrapping-up transition stalls on the client even though it succeeded
/// on the server.
///
/// This test drives the real `GBeaconCloseReq` through a Ferry [Client] with a
/// link that mimics the actual server payload, and asserts the response
/// deserializes cleanly.
class _FakeLink extends Link {
  _FakeLink(this.response);

  final Response response;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) =>
      Stream.value(response);
}

void main() {
  test('beaconClose deserializes the real server payload shape', () async {
    final client = Client(
      link: _FakeLink(
        const Response(
          data: {
            '__typename': 'mutation_root',
            'beaconClose': {
              '__typename': 'v2_BeaconCloseResult',
              'id': 'Baaaaaaaaaaaa',
              'status': 3,
              'closesAt': null,
            },
          },
          response: {},
        ),
      ),
      // Mutations run NoCache in production (see build_client.dart), so Ferry
      // parses the link payload directly — exactly the boundary that broke.
      defaultFetchPolicies: const {
        OperationType.mutation: FetchPolicy.NoCache,
      },
    );

    final response = await client
        .request(
          GBeaconCloseReq(
            (b) => b.vars
              ..id = 'Baaaaaaaaaaaa'
              ..expectedRequiresReviewWindow = true,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link);

    final data = response.dataOrThrow(label: 'test');
    expect(data.beaconClose.id, 'Baaaaaaaaaaaa');
    expect(data.beaconClose.status, 3);
    expect(data.beaconClose.closesAt, isNull);
  });
}

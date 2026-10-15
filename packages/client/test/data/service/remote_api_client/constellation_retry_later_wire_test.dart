import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/constellation/data/repository/constellation_anchor_repository.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'retry_later_wire_support.dart';

// Server admission answers an overlapping heavy constellation read with the
// typed code 1704 and a `retryAfterMs` hint (same wire shape as the server's
// ConstellationException.toMap). These tests drive the real RemoteApiService
// over a stubbed HTTP server, so they pin the behaviour at the transport edge
// regardless of which layer performs the retry.

// Large enough that a fixed one-second sleep, or no wait at all, cannot pass
// for "honours the hint".
const _retryAfterMs = 600;
const _jitterAllowanceMs = 250;

Map<String, Object?> _emptyFieldPayload() => {
  '__typename': 'v2_ConstellationField',
  'loadedAt': '2026-10-15T12:00:00.000Z',
  'context': '',
  'peersCapped': false,
  'requestsCapped': false,
  'peers': <Object?>[],
  'edges': <Object?>[],
  'requests': <Object?>[],
  'posts': <Object?>[],
  'memberWebs': <Object?>[],
  'anchorProjection': {
    '__typename': 'v2_ConstellationAnchorProjection',
    'revision': '0',
    'anchors': <Object?>[],
    'pinnedPeers': <Object?>[],
    'pinnedRequests': <Object?>[],
    'supportPeers': <Object?>[],
    'supportEdges': <Object?>[],
    'serverFilteredBeaconIds': <Object?>[],
    'serverFilteredBeaconCount': 0,
  },
};

http.Response _fieldResponse() => jsonResponse({
  'data': {
    '__typename': 'query_root',
    'constellationField': _emptyFieldPayload(),
  },
});

ConstellationAnchorApplyOp _upsertOp() => ConstellationAnchorApplyOp(
  clientOpId: 'op-place',
  kind: ConstellationAnchorOpKind.upsert,
  target: ConstellationAnchorTarget.person('Upeer'),
  position: const ConstellationAnchorPosition(
    xUnits: 1.5,
    yUnits: 2.5,
    coordinateSpaceVersion: 1,
  ),
);

void main() {
  group('constellation read retry on server admission backoff', () {
    test('a read rejected once succeeds after the advertised delay without '
        'surfacing an error', () async {
      final server = stubServer(
        (call, attempt) =>
            attempt == 1 ? retryLaterResponse(_retryAfterMs) : _fieldResponse(),
      );

      // Completing normally (no throw) is what keeps the busy answer away from
      // the user-facing error path that reports to Sentry.
      final field = await withRemote(
        server.client,
        (remote) => ConstellationRepository(remote).fetch(),
      );

      expect(field.loadedAt, DateTime.utc(2026, 10, 15, 12));
      expect(server.calls.map((c) => c.operation).toSet(), {
        'ConstellationFieldFetch',
      });
      expect(server.calls, hasLength(2));
      final waited = server.calls[1].at.difference(server.calls[0].at);
      expect(
        waited,
        greaterThanOrEqualTo(const Duration(milliseconds: _retryAfterMs - 10)),
        reason: 'the retry must honour the retryAfterMs hint',
      );
      expect(
        waited,
        lessThan(
          const Duration(milliseconds: _retryAfterMs + _jitterAllowanceMs),
        ),
        reason: 'the wait is the hint plus a small jitter, not a fixed sleep',
      );
    });

    test('once the attempt cap is reached the last retry-later error is '
        'thrown exactly once', () async {
      // Each answer carries a different hint, so the surfaced error can be
      // traced to the final attempt.
      final server = stubServer(
        (call, attempt) => retryLaterResponse(10 * attempt),
      );

      final failures = <Object>[];
      await withRemote(server.client, (remote) async {
        try {
          await ConstellationRepository(remote).fetch();
        } on RemoteApiRetryLaterException catch (error) {
          failures.add(error);
        }
      });
      expect(failures, isNotEmpty, reason: 'the read must not succeed');

      expect(
        server.calls.length,
        inInclusiveRange(2, 3),
        reason: 'two or three attempts in total, never more',
      );
      expect(failures, hasLength(1));
      expect(
        failures.single,
        isA<RemoteApiRetryLaterException>().having(
          (e) => e.retryAfter,
          'retryAfter',
          Duration(milliseconds: 10 * server.calls.length),
        ),
        reason: 'the error of the last attempt surfaces',
      );
      for (var i = 1; i < server.calls.length; i++) {
        expect(
          server.calls[i].at.difference(server.calls[i - 1].at),
          greaterThanOrEqualTo(Duration(milliseconds: 10 * i - 5)),
          reason: 'retry $i waits for the hint of the attempt before it',
        );
      }
    });

    test('a mutation rejected with retry-later is not retried', () async {
      final server = stubServer((call, attempt) => retryLaterResponse(10));

      await expectLater(
        withRemote(
          server.client,
          (remote) => ConstellationAnchorRepository(remote).apply(
            ops: [_upsertOp()],
            params: ConstellationFieldMembershipFilters.defaults,
          ),
        ),
        throwsA(isA<RemoteApiRetryLaterException>()),
      );

      expect(server.calls.map((c) => c.operation), [
        'ConstellationAnchorsApply',
      ]);
    });

    test(
      'concurrent reads that are each rejected once all recover',
      () async {
        final server = stubServer(
          (call, attempt) => attempt == 1
              ? retryLaterResponse(_retryAfterMs)
              : _fieldResponse(),
        );

        final fields = await withRemote(server.client, (remote) {
          final repository = ConstellationRepository(remote);
          return (
            repository.fetch(),
            repository.fetch(
              membershipFilters: const ConstellationFieldMembershipFilters(
                showClosed: true,
              ),
            ),
          ).wait;
        });

        expect(fields.$1.loadedAt, DateTime.utc(2026, 10, 15, 12));
        expect(fields.$2.loadedAt, DateTime.utc(2026, 10, 15, 12));
      },
    );
  });
}

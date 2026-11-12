// Pins error propagation of the two parallel loads in the forward feature:
// ForwardRepository.fetchBeaconInvolvement and
// ForwardCase.loadForwardCandidates. When one of the parallel futures fails,
// the caller must see that future's original exception (not a wrapper such as
// ParallelWaitError), and when both fail the first error to arrive wins.
import 'dart:async';

import 'package:ferry/ferry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';

import '../../support/test_forward_case.dart';

class _BeaconBoom implements Exception {}

class _InvolvementBoom implements Exception {}

class _CandidatesBoom implements Exception {}

class _FakeBeaconRepository implements BeaconRepository {
  _FakeBeaconRepository(this.result);

  final Future<Beacon> Function() result;

  @override
  Future<Beacon> fetchBeaconById(String id) => result();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ErrorStreamClient implements RemoteRequestClient {
  _ErrorStreamClient(this.error, {this.delay = Duration.zero});

  final Exception error;
  final Duration delay;

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) => Stream.fromFuture(
    Future<OperationResponse<TData, TVars>>.delayed(delay, () => throw error),
  );
}

final class _QuietRealtimeSync implements RealtimeSyncPort {
  @override
  Stream<RealtimeEntityChange> get entityChanges => const Stream.empty();

  @override
  Stream<RealtimeCatchUp> get catchUps => const Stream.empty();

  @override
  Stream<RealtimeConnectionStatus> get connectionStatuses =>
      const Stream.empty();

  @override
  void requestCatchUp(RealtimeCatchUpReason reason) {}

  @override
  Future<void> dispose() async {}
}

ForwardRepository _repository({
  required Future<Beacon> Function() beacon,
  required RemoteRequestClient remote,
}) => ForwardRepository(
  remote,
  _FakeBeaconRepository(beacon),
  _QuietRealtimeSync(),
);

class _ThrowingForwardRepository implements ForwardRepository {
  _ThrowingForwardRepository({
    required this.candidates,
    required this.involvement,
  });

  final Future<Iterable<Profile>> Function() candidates;
  final Future<BeaconInvolvementData> Function() involvement;

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({String context = ''}) =>
      candidates();

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) => involvement();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _later = Duration(milliseconds: 20);

void main() {
  group('ForwardRepository.fetchBeaconInvolvement error propagation', () {
    test('involvement request failure reaches the caller as-is', () async {
      final repository = _repository(
        beacon: () async => Beacon.empty,
        remote: _ErrorStreamClient(_InvolvementBoom()),
      );

      await expectLater(
        repository.fetchBeaconInvolvement(beaconId: 'b1'),
        throwsA(isA<_InvolvementBoom>()),
      );
    });

    test('beacon fetch failure reaches the caller as-is', () async {
      final repository = _repository(
        beacon: () => Future<Beacon>.error(_BeaconBoom()),
        remote: _ErrorStreamClient(_InvolvementBoom(), delay: _later),
      );

      await expectLater(
        repository.fetchBeaconInvolvement(beaconId: 'b1'),
        throwsA(isA<_BeaconBoom>()),
      );
    });

    test(
      'involvement failing first wins over a later beacon failure',
      () async {
        final repository = _repository(
          beacon: () =>
              Future<Beacon>.delayed(_later, () => throw _BeaconBoom()),
          remote: _ErrorStreamClient(_InvolvementBoom()),
        );

        await expectLater(
          repository.fetchBeaconInvolvement(beaconId: 'b1'),
          throwsA(isA<_InvolvementBoom>()),
        );
      },
    );
  });

  group('ForwardCase.loadForwardCandidates error propagation', () {
    test('candidates failure reaches the caller as-is', () async {
      final forwardCase = buildTestForwardCase(
        _ThrowingForwardRepository(
          candidates: () => Future<Iterable<Profile>>.error(_CandidatesBoom()),
          involvement: () => Future<BeaconInvolvementData>.delayed(
            _later,
            () => throw _InvolvementBoom(),
          ),
        ),
      );

      await expectLater(
        forwardCase.loadForwardCandidates(beaconId: 'b1'),
        throwsA(isA<_CandidatesBoom>()),
      );
    });

    test('involvement failure reaches the caller as-is', () async {
      final forwardCase = buildTestForwardCase(
        _ThrowingForwardRepository(
          candidates: () async => const <Profile>[],
          involvement: () =>
              Future<BeaconInvolvementData>.error(_InvolvementBoom()),
        ),
      );

      await expectLater(
        forwardCase.loadForwardCandidates(beaconId: 'b1'),
        throwsA(isA<_InvolvementBoom>()),
      );
    });
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/profile_view/data/repository/profile_shared_beacons_repository.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_shared_beacons_case.dart';
import 'package:tentura/features/profile_view/ui/bloc/profile_shared_beacons_cubit.dart';

import '../../support/test_realtime_sync.dart';

void main() {
  group('Profile shared Requests realtime convergence', () {
    late _SharedBeaconsHarness harness;

    setUp(() => harness = _SharedBeaconsHarness());

    tearDown(() => harness.dispose());

    test(
      'beacon, forward, and help bursts coalesce into a silent refresh',
      () async {
        harness.start();
        await harness.waitFor(() => harness.repository.fetchCalls == 1);
        harness.repository.result = _data('B-updated');

        for (final kind in const {
          RealtimeEntityKind.beacon,
          RealtimeEntityKind.forward,
          RealtimeEntityKind.helpOffer,
        }) {
          harness.realtimePort.emitChange(
            RealtimeEntityChange(
              kind: kind,
              aggregateId: 'B-updated',
              operation: RealtimeOperation.update,
              source: RealtimeChangeSource.serverInvalidation,
            ),
          );
        }
        await harness.waitFor(() => harness.currentBeaconId == 'B-updated');

        expect(harness.repository.fetchCalls, 2);
        expect(harness.cubit.state.isSuccess, isTrue);
      },
    );

    test('catch-up replaces a missed shared Request change', () async {
      harness.start();
      await harness.waitFor(() => harness.repository.fetchCalls == 1);
      harness.repository.result = _data('B-caught-up');

      harness.realtimePort.emitCatchUp();
      await harness.waitFor(() => harness.currentBeaconId == 'B-caught-up');

      expect(harness.cubit.state.loadError, isNull);
    });

    test('stale completion cannot replace a newer projection', () async {
      harness.start();
      await harness.waitFor(() => harness.repository.fetchCalls == 1);
      final stale = Completer<ProfileSharedBeaconsData>();
      final fresh = Completer<ProfileSharedBeaconsData>();
      harness.repository.pending.addAll([stale, fresh]);

      final staleFetch = harness.cubit.fetch(showLoading: false);
      final freshFetch = harness.cubit.fetch(showLoading: false);
      await harness.waitFor(() => harness.repository.pending.isEmpty);
      fresh.complete(_data('B-fresh'));
      await freshFetch;
      stale.complete(_data('B-stale'));
      await staleFetch;

      expect(harness.currentBeaconId, 'B-fresh');
    });

    test('background failure keeps the usable projection', () async {
      harness.start();
      await harness.waitFor(() => harness.repository.fetchCalls == 1);
      harness.repository.error = StateError('offline');

      harness.realtimePort.emitCatchUp();
      await harness.waitFor(() => harness.repository.fetchCalls == 2);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(harness.currentBeaconId, 'B-initial');
      expect(harness.cubit.state.loadError, isNull);
    });
  });
}

ProfileSharedBeaconsData _data(String beaconId) => (
  forwarded: [
    (
      edgeId: 'edge-$beaconId',
      beacon: Beacon(
        id: beaconId,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      note: '',
      recipientRejected: false,
      recipientRejectionMessage: '',
      reaction: TargetBeaconReaction.none,
    ),
  ],
  coHelpOffered: const [],
);

final class _SharedBeaconsHarness {
  _SharedBeaconsHarness() {
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    realtimeCase = realtime.case_;
    case_ = ProfileSharedBeaconsCase(
      repository,
      realtimeCase,
      env: const Env(),
      logger: Logger('test'),
    );
  }

  final repository = _FakeSharedBeaconsRepository();

  late final TestRealtimeSyncPort realtimePort;
  late final RealtimeSyncCase realtimeCase;
  late final ProfileSharedBeaconsCase case_;
  ProfileSharedBeaconsCubit? _cubit;

  ProfileSharedBeaconsCubit get cubit => _cubit!;

  String? get currentBeaconId =>
      cubit.state.data?.forwarded.firstOrNull?.beacon.id;

  void start() {
    _cubit = ProfileSharedBeaconsCubit(
      meId: 'U-me',
      targetId: 'U-target',
      profileSharedBeaconsCase: case_,
    );
  }

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Timed out waiting for shared Request convergence.');
  }

  Future<void> dispose() async {
    await _cubit?.close();
    await realtimePort.dispose();
  }
}

final class _FakeSharedBeaconsRepository
    implements ProfileSharedBeaconsRepository {
  ProfileSharedBeaconsData result = _data('B-initial');
  Object? error;
  int fetchCalls = 0;
  final pending = <Completer<ProfileSharedBeaconsData>>[];

  @override
  Future<ProfileSharedBeaconsData> fetch({
    required String meId,
    required String targetId,
  }) async {
    fetchCalls++;
    if (pending.isNotEmpty) return pending.removeAt(0).future;
    final failure = error;
    if (failure is Exception) throw failure;
    if (failure is Error) throw failure;
    return result;
  }
}

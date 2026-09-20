import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/domain/exception.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_open_clear_listener.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';

import 'package:tentura/domain/use_case/realtime_sync_case.dart';

import '../../domain/attention/attention_case_test_support.dart';
import '../block/support/controllable_block_case.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

void main() {
  const myProfile = Profile(id: 'Uviewer', displayName: 'Viewer');

  Beacon beaconOf(String id) => Beacon(
    id: id,
    title: 'Request $id',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    status: BeaconStatus.open,
    canReadContent: true,
    author: const Profile(id: 'Uauthor', displayName: 'Author'),
  );

  /// Mounts the production listener over a real [BeaconViewCubit], so the
  /// success/failure signal is the cubit's own, not the test's.
  Future<
    ({
      List<String> clears,
      TrackingBeaconRepository repo,
      ({RealtimeSyncCase case_, TestRealtimeSyncPort port}) realtime,
    })
  >
  mount(
    WidgetTester tester, {
    required String beaconId,
    required Future<Beacon> Function(String id) fetch,
  }) async {
    final clears = <String>[];
    final repo = TrackingBeaconRepository()..fetchByIdHandler = fetch;
    final realtime = buildTestRealtimeSync();
    addTearDown(realtime.port.dispose);
    final cubit = BeaconViewCubit(
      id: beaconId,
      myProfile: myProfile,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: repo,
        realtimeSyncCase: realtime.case_,
      ),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<BeaconViewCubit>.value(
          value: cubit,
          child: BeaconOpenClearListener(
            beaconId: beaconId,
            clear: ({required String beaconId}) async => clears.add(beaconId),
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    // The cubit's one retry sleeps 300ms before the second attempt.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    return (clears: clears, repo: repo, realtime: realtime);
  }

  group('opening a Request clears it, after it displays', () {
    testWidgets('a successful open clears exactly that Request', (
      tester,
    ) async {
      final r = await mount(
        tester,
        beaconId: 'Bparent',
        fetch: (id) async => beaconOf(id),
      );

      expect(r.repo.fetchByIdCalls, greaterThan(0));
      expect(r.clears, ['Bparent']);
    });

    testWidgets('opening a child clears the child only', (tester) async {
      final r = await mount(
        tester,
        beaconId: 'Bchild',
        fetch: (id) async => beaconOf(id),
      );

      expect(r.clears, ['Bchild']);
      expect(r.clears, isNot(contains('Bparent')));
    });

    testWidgets('a forbidden open clears nothing — and did navigate', (
      tester,
    ) async {
      final r = await mount(
        tester,
        beaconId: 'Bforbidden',
        fetch: (_) async => throw const BeaconFetchException(),
      );

      // The failure path was genuinely exercised: the screen mounted, the
      // cubit ran its fetch and reported unavailable.
      expect(r.repo.fetchByIdCalls, greaterThanOrEqualTo(1));
      final cubit = tester
          .element(find.byType(BeaconOpenClearListener))
          .read<BeaconViewCubit>();
      expect(cubit.state.beaconUnavailable, isTrue);
      expect(cubit.state.beaconContentLoaded, isFalse);
      expect(r.clears, isEmpty);
    });

    testWidgets('a failed open that later retries clears once, on success', (
      tester,
    ) async {
      var attempt = 0;
      final r = await mount(
        tester,
        beaconId: 'Bretry',
        fetch: (id) async {
          attempt++;
          if (attempt <= 2) throw const BeaconFetchException();
          return beaconOf(id);
        },
      );
      expect(r.clears, isEmpty, reason: 'the first open failed');

      final cubit = tester
          .element(find.byType(BeaconOpenClearListener))
          .read<BeaconViewCubit>();
      unawaited(cubit.retryInitialLoad());
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(r.clears, ['Bretry']);
    });

    testWidgets('a background refresh clears nothing', (tester) async {
      final r = await mount(
        tester,
        beaconId: 'Brefresh',
        fetch: (id) async => beaconOf(id),
      );
      expect(r.clears, ['Brefresh']);

      final before = r.repo.fetchByIdCalls;
      r.realtime.port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.profile,
          aggregateId: 'Uauthor',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      // The refresh really happened; it just is not a gesture (§4).
      expect(r.repo.fetchByIdCalls, greaterThan(before));
      expect(r.clears, ['Brefresh'], reason: 'a refresh is not an opening');
    });
  });

  testWidgets(
    'by default it clears through AttentionCase.clearRequestOpen — the kind '
    'whose capture excludes obligations',
    (tester) async {
      final repo = AttentionCaseTestRepository()
        ..clearSnapshots.add(
          const AttentionClearSnapshot(snapshotToken: 'snap', receiptIds: []),
        )
        ..pendingClears.add(
          Completer<AttentionClearResult>()..complete(
            const AttentionClearResult(
              operationId: 'op',
              status: AttentionOperationStatus.complete,
            ),
          ),
        );
      final accounts = AttentionCaseTestAccounts();
      addTearDown(accounts.dispose);
      final attention = AttentionCase(
        repo,
        accounts,
        buildTestRealtimeSync().case_,
        noopBlockCase(),
        FeedSessionRegistry(),
        Logger('BeaconOpenClearListenerTest'),
        qaLatencyMeasurementEnabled: false,
      );
      addTearDown(attention.dispose);
      if (GetIt.I.isRegistered<AttentionCase>()) {
        await GetIt.I.unregister<AttentionCase>();
      }
      GetIt.I.registerSingleton<AttentionCase>(attention);
      addTearDown(() => GetIt.I.unregister<AttentionCase>());

      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (id) async => beaconOf(id);
      final cubit = BeaconViewCubit(
        id: 'Bdefault',
        myProfile: myProfile,
        beaconViewCase: buildTestBeaconViewCase(beaconRepo: beaconRepo),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<BeaconViewCubit>.value(
            value: cubit,
            // No `clear` override: the production path.
            child: const BeaconOpenClearListener(
              beaconId: 'Bdefault',
              child: SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.clearSnapshotCalls, [
        (kind: AttentionClearCaptureKind.requestOpen, beaconId: 'Bdefault'),
      ]);
    },
  );
}

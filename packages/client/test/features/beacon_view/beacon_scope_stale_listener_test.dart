import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_state.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_open_clear_listener.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_status_sync.dart';

/// A [BeaconViewCubit] the test drives by hand: no case, no fetch, no timers.
class _FakeBeaconViewCubit extends Mock implements BeaconViewCubit {
  _FakeBeaconViewCubit(this._state);

  BeaconViewState _state;
  final _controller = StreamController<BeaconViewState>.broadcast();

  void emitState(BeaconViewState value) {
    _state = value;
    _controller.add(value);
  }

  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => _controller.stream;

  @override
  Future<void> close() => _controller.close();
}

/// Records what [BeaconStatusSync] pushes into the room host.
class _RecordingHost extends Mock implements ThreadHostCubit {
  final synced = <BeaconStatus>[];

  @override
  ThreadHostState get state => const ThreadHostState();

  @override
  Stream<ThreadHostState> get stream => const Stream.empty();

  @override
  void syncBeaconStatus(
    BeaconStatus status, {
    String? authorId,
    bool expired = false,
  }) => synced.add(status);
}

/// A descendant whose teardown fails. Flutter then stops unmounting the
/// removed subtree (`finalizeTree` reports the error and moves on): its
/// ancestors stay deactivated, never disposed, and their stream listeners
/// outlive the screen.
class _FailsOnDispose extends StatefulWidget {
  const _FailsOnDispose();

  @override
  State<_FailsOnDispose> createState() => _FailsOnDisposeState();
}

class _FailsOnDisposeState extends State<_FailsOnDispose> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  @override
  void dispose() {
    super.dispose();
    throw StateError('teardown failed');
  }
}

void main() {
  const myProfile = Profile(id: 'Uviewer', displayName: 'Viewer');
  const timeout = Timeout(Duration(seconds: 30));

  final beacon = Beacon(
    id: 'B1',
    title: 'Request B1',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    author: const Profile(id: 'Uauthor', displayName: 'Author'),
  );
  final loading = BeaconViewState(beacon: beacon, myProfile: myProfile);
  final loaded = loading.copyWith(beaconContentLoaded: true);

  /// The listeners `BeaconViewScope` mounts, in its order.
  Future<
    ({_FakeBeaconViewCubit cubit, _RecordingHost host, List<String> clears})
  >
  mount(WidgetTester tester, {Widget child = const SizedBox.shrink()}) async {
    final cubit = _FakeBeaconViewCubit(loading);
    addTearDown(cubit.close);
    final host = _RecordingHost();
    final clears = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<BeaconViewCubit>.value(value: cubit),
            BlocProvider<ThreadHostCubit>.value(value: host),
          ],
          child: BeaconStatusSync(
            child: BeaconOpenClearListener(
              beaconId: 'B1',
              clear: ({required beaconId}) async => clears.add(beaconId),
              child: child,
            ),
          ),
        ),
      ),
    );
    return (cubit: cubit, host: host, clears: clears);
  }

  testWidgets('in the tree: the load syncs the room host and clears', (
    tester,
  ) async {
    final r = await mount(tester);

    r.cubit.emitState(loaded);
    await tester.pump();

    expect(r.host.synced, [BeaconStatus.open]);
    expect(r.clears, ['B1']);
  }, timeout: timeout);

  // #745 (Sentry TENTURA-CLIENT-4D): the Request loaded after the viewer had
  // left it; the stale status listener looked the room host up from a
  // context no longer in the tree (ProviderNotFound in release builds, the
  // deactivated-ancestor assertion in debug).
  testWidgets('a load landing after the Request left looks nothing up', (
    tester,
  ) async {
    final r = await mount(tester, child: const _FailsOnDispose());

    // Leave the Request while it is still loading.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(tester.takeException(), isStateError);

    // The load lands afterwards and reaches the stale listeners.
    r.cubit.emitState(loaded);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(r.host.synced, isEmpty);
    expect(r.clears, isEmpty, reason: 'it never displayed');
  }, timeout: timeout);
}

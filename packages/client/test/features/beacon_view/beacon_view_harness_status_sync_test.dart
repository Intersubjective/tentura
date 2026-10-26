import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'beacon_view_screen_harness.dart';

/// #415 / #619: in the app `BeaconViewScope` pushes the Request's status and
/// author into the room host. The screen harness mounts the same sync, so a
/// test no longer has to call `host.syncBeaconStatus` by hand to get a room
/// that is not read-only.
class _RecordingHost extends ThreadHostCubit {
  _RecordingHost(BeaconViewRoomCubitRecorder recorder)
    : super(
        beaconId: kBeaconViewHarnessBeaconId,
        roomCubitFactory:
            ({
              required beaconId,
              threadItemId,
              initialUnreadAnchorAt,
              RoomCapabilities? capabilities,
            }) => recorder.call(
              beaconId: beaconId,
              threadItemId: threadItemId,
              initialUnreadAnchorAt: initialUnreadAnchorAt,
            ),
      );

  final synced = <(BeaconStatus, String?)>[];

  @override
  void syncBeaconStatus(BeaconStatus status, {String? authorId}) {
    synced.add((status, authorId));
    super.syncBeaconStatus(status, authorId: authorId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(registerBeaconViewHarnessGetIt);
  tearDown(unregisterBeaconViewHarnessGetIt);

  Future<_RecordingHost> pump(
    WidgetTester tester, {
    BeaconStatus status = BeaconStatus.enoughHelp,
    bool sync = true,
  }) async {
    final recorder = BeaconViewRoomCubitRecorder();
    final host = _RecordingHost(recorder);
    final state = beaconViewHarnessAuthorState();
    await pumpBeaconViewHarness(
      tester,
      size: kBeaconViewHarnessExpanded,
      beaconState: state.copyWith(
        beacon: state.beacon.copyWith(status: status),
      ),
      threadsState: beaconViewHarnessThreadsState(),
      host: host,
      recorder: recorder,
      syncBeaconStatus: sync,
    );
    return host;
  }

  testWidgets('the harness syncs the loaded status and author into the host', (
    tester,
  ) async {
    final host = await pump(tester);

    expect(host.synced, [
      (BeaconStatus.enoughHelp, kBeaconViewHarnessAuthorId),
    ]);
  });

  testWidgets('a test can opt out and keep the host unsynced', (tester) async {
    final host = await pump(tester, sync: false);

    expect(host.synced, isEmpty);
  });
}

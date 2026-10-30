import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';

import '../../support/burst_coalescer_test_timing.dart';
import 'room_cubit_fakes.dart';

/// Waits for a reply-jump refresh in `room_cubit_reply_test.dart`: the expected
/// message fetch count is reached and [reflectsRefreshedSnapshot] is true on
/// [cubit] before this future completes.
Future<void> awaitRoomReplyRefreshSettled({
  required FakeBeaconThreadsRepository room,
  required RoomCubit cubit,
  required int expectedFetchCount,
  required bool Function() reflectsRefreshedSnapshot,
}) async {
  final deadline = DateTime.now().add(burstCoalescerSettleTimeout);
  while (DateTime.now().isBefore(deadline)) {
    if (room.fetchMessagesCallCount >= expectedFetchCount &&
        reflectsRefreshedSnapshot()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'Expected at least $expectedFetchCount message fetches '
    '(got ${room.fetchMessagesCallCount}) with refreshed cubit snapshot '
    '(reflectsRefreshedSnapshot=${reflectsRefreshedSnapshot()}).',
  );
}

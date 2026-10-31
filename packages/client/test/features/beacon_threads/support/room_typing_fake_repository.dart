import 'dart:async';

import 'package:tentura/features/beacon_threads/domain/entity/room_typing_signal.dart';

import '../room_cubit_fakes.dart';

/// A room repository that relays typing the way the server's socket does:
/// signals pushed through [relay] reach the room, and every typing intent the
/// room's composer sends is recorded in [intents] (with its time in
/// [intentTimes]).
class RoomTypingFakeRepository extends FakeBeaconThreadsRepository {
  RoomTypingFakeRepository() : super(userId: kRoomCubitFakeMyUserId);

  final signals = StreamController<RoomTypingSignal>.broadcast();

  /// `true` = start / refresh, `false` = stop, in send order.
  final intents = <bool>[];

  final intentTimes = <DateTime>[];

  final intentBeaconIds = <String>[];

  @override
  Stream<RoomTypingSignal> get roomTypingSignals => signals.stream;

  @override
  void sendRoomTyping({required String beaconId, required bool typing}) {
    intentBeaconIds.add(beaconId);
    intents.add(typing);
    intentTimes.add(DateTime.now());
  }

  void relay(String userId, {bool typing = true, String? beaconId}) =>
      signals.add(
        RoomTypingSignal(
          beaconId: beaconId ?? kRoomCubitFakeBeaconId,
          userId: userId,
          typing: typing,
        ),
      );
}

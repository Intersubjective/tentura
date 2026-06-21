import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart' show RoomCubit;

/// Notifies main-room [RoomCubit] instances when a coordination item changes
/// (e.g. resolve in item thread) so the timeline can patch before WS echo.
@lazySingleton
class CoordinationItemRoomSync {
  final _controller = StreamController<CoordinationItem>.broadcast();

  Stream<CoordinationItem> get changes => _controller.stream;

  void notifyItemUpdated(CoordinationItem item) {
    if (_controller.isClosed) return;
    _controller.add(item);
  }

  @disposeMethod
  Future<void> dispose() async {
    await _controller.close();
  }
}

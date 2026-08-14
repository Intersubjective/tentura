import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/coordination_item.dart';

/// Notifies main-room consumers when a coordination item changes so timelines can
/// patch item snapshots before WS echo.
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

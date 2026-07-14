import 'dart:async';

import 'package:injectable/injectable.dart';

@singleton
class BookkeepingRefreshSignal {
  final _controller = StreamController<void>.broadcast();

  Stream<void> get stream => _controller.stream;

  void notify() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }

  @disposeMethod
  Future<void> dispose() async {
    await _controller.close();
  }
}

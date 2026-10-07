import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:tentura/domain/port/wake_up_port.dart';

@LazySingleton(as: WakeUpPort, env: [Environment.dev, Environment.prod])
final class WakeUpService implements WakeUpPort {
  @override
  WakeUpHandle schedule(Duration delay, void Function() callback) =>
      _TimerWakeUpHandle(Timer(delay, callback));
}

final class _TimerWakeUpHandle implements WakeUpHandle {
  _TimerWakeUpHandle(this._timer);

  final Timer _timer;

  @override
  bool get isActive => _timer.isActive;

  @override
  void cancel() => _timer.cancel();
}

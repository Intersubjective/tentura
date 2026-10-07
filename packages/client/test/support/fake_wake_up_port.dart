import 'package:tentura/domain/port/wake_up_port.dart';

/// [WakeUpPort] whose timers fire only when the test calls [elapse].
final class FakeWakeUpPort implements WakeUpPort {
  final _pending = <_FakeWakeUp>[];

  Duration _elapsed = Duration.zero;

  int get pendingCount => _pending.where((w) => w.isActive).length;

  @override
  WakeUpHandle schedule(Duration delay, void Function() callback) {
    final wakeUp = _FakeWakeUp(_elapsed + delay, callback);
    _pending.add(wakeUp);
    return wakeUp;
  }

  /// Moves time forward, firing every due active wake-up in due order.
  void elapse(Duration by) {
    final target = _elapsed + by;
    while (true) {
      final due =
          _pending.where((w) => w.isActive && w.dueAt <= target).toList()
            ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
      if (due.isEmpty) break;
      final next = due.first;
      _elapsed = next.dueAt;
      next.fire();
    }
    _elapsed = target;
    _pending.removeWhere((w) => !w.isActive);
  }
}

final class _FakeWakeUp implements WakeUpHandle {
  _FakeWakeUp(this.dueAt, this._callback);

  final Duration dueAt;

  final void Function() _callback;

  var _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() => _active = false;

  void fire() {
    _active = false;
    _callback();
  }
}

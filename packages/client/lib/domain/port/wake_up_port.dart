/// Schedules a single wake-up without exposing platform timers to the domain.
// ignore: one_member_abstracts -- injectable boundary with a test replacement
abstract interface class WakeUpPort {
  WakeUpHandle schedule(Duration delay, void Function() callback);
}

abstract interface class WakeUpHandle {
  bool get isActive;

  void cancel();
}

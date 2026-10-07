import 'package:tentura/domain/port/clock_port.dart';

/// Manually advanced [ClockPort] for deterministic domain tests.
final class FakeClockPort implements ClockPort {
  FakeClockPort([DateTime? start]) : _now = start ?? DateTime.utc(2026);

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration by) => _now = _now.add(by);

  // A setter would read oddly next to `now()`.
  // ignore: use_setters_to_change_properties
  void set(DateTime value) => _now = value;
}

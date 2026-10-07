import 'package:injectable/injectable.dart';
import 'package:tentura/domain/port/clock_port.dart';

@LazySingleton(as: ClockPort, env: [Environment.dev, Environment.prod])
final class ClockService implements ClockPort {
  @override
  DateTime now() => DateTime.now();
}

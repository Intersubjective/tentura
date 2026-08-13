import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/port/capability_telemetry_port.dart';
import 'package:tentura_server/domain/port/routing_mute_port.dart';
import 'package:tentura_server/domain/use_case/capability_telemetry_case.dart';
import 'package:tentura_server/env.dart';

class _FakeRoutingMutePort implements RoutingMutePort {
  Map<String, int> counts = const {};

  @override
  Future<Map<String, int>> muteCountsByTag() async => counts;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

class _FakeCapabilityTelemetryPort implements CapabilityTelemetryPort {
  ({int seedTriples, int renewed}) counts = (seedTriples: 0, renewed: 0);

  @override
  Future<({int seedTriples, int renewed})> countSeedRenewal() async => counts;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

void main() {
  late _FakeRoutingMutePort routingMute;
  late _FakeCapabilityTelemetryPort telemetry;
  late CapabilityTelemetryCase case_;

  const fixtureUserA = 'UcapG1bFixtureAlice01';
  const fixtureUserB = 'UcapG1bFixtureBob01';

  setUp(() {
    routingMute = _FakeRoutingMutePort();
    telemetry = _FakeCapabilityTelemetryPort();
    case_ = CapabilityTelemetryCase(
      routingMute,
      telemetry,
      env: Env(environment: Environment.test),
      logger: Logger('CapabilityTelemetryCaseTest'),
    );
  });

  group('capability telemetry (G1b)', () {
    test('runDue logs mute counts sorted by slug without user ids', () async {
      final records = <LogRecord>[];
      Logger('CapabilityTelemetryCaseTest').onRecord.listen(records.add);

      routingMute.counts = {
        'transport': 3,
        'pets': 2,
      };
      telemetry.counts = (seedTriples: 0, renewed: 0);

      await case_.runDue(now: DateTime.utc(2026, 8, 13));

      final muteLines = records
          .where((r) => r.message.startsWith('capability_mute_rate'))
          .toList();
      expect(muteLines, hasLength(1));
      final message = muteLines.single.message;
      expect(message, 'capability_mute_rate pets=2 transport=3');
      expect(message, isNot(contains(fixtureUserA)));
      expect(message, isNot(contains(fixtureUserB)));
    });

    test('runDue logs seed renewal counts without user ids', () async {
      final records = <LogRecord>[];
      Logger('CapabilityTelemetryCaseTest').onRecord.listen(records.add);

      routingMute.counts = const {};
      telemetry.counts = (seedTriples: 7, renewed: 3);

      await case_.runDue(now: DateTime.utc(2026, 8, 13));

      final seedLines = records
          .where((r) => r.message.startsWith('capability_seed_renewal'))
          .toList();
      expect(seedLines, hasLength(1));
      final message = seedLines.single.message;
      expect(message, contains('seed_triples=7'));
      expect(message, contains('renewed=3'));
      expect(message, isNot(contains(fixtureUserA)));
      expect(message, isNot(contains(fixtureUserB)));
    });

    test('runDue logs empty mute line when no mutes exist', () async {
      final records = <LogRecord>[];
      Logger('CapabilityTelemetryCaseTest').onRecord.listen(records.add);

      routingMute.counts = const {};
      telemetry.counts = (seedTriples: 1, renewed: 0);

      await case_.runDue(now: DateTime.utc(2026, 8, 13));

      final muteLines = records
          .where((r) => r.message.startsWith('capability_mute_rate'))
          .toList();
      expect(muteLines, hasLength(1));
      expect(muteLines.single.message, 'capability_mute_rate');
    });
  });
}

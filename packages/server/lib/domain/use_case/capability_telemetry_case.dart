import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/capability_telemetry_port.dart';
import 'package:tentura_server/domain/port/routing_mute_port.dart';
import 'package:tentura_server/domain/use_case/_use_case_base.dart';

@Singleton(order: 2)
final class CapabilityTelemetryCase extends UseCaseBase {
  CapabilityTelemetryCase(
    this._routingMute,
    this._telemetry,
    {
    required super.env,
    required super.logger,
  });

  final RoutingMutePort _routingMute;
  final CapabilityTelemetryPort _telemetry;

  Future<void> runDue({required DateTime now}) async {
    await _logMuteRates();
    await _logSeedRenewal();
  }

  Future<void> _logMuteRates() async {
    final counts = await _routingMute.muteCountsByTag();
    final parts = counts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final suffix = parts.map((e) => '${e.key}=${e.value}').join(' ');
    logger.info(
      suffix.isEmpty ? 'capability_mute_rate' : 'capability_mute_rate $suffix',
    );
  }

  Future<void> _logSeedRenewal() async {
    final counts = await _telemetry.countSeedRenewal();
    logger.info(
      'capability_seed_renewal seed_triples=${counts.seedTriples} '
      'renewed=${counts.renewed}',
    );
  }
}

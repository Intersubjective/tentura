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
    await _logTwoHopSponsoredMr();
    await _logEligibleWitnessCoverage();
    await _logReciprocalAcknowledgementRings();
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

  Future<void> _logTwoHopSponsoredMr() async {
    final summary = await _telemetry.twoHopSponsoredForwardMrPercentiles();
    if (summary.n == 0) {
      logger.info('witness_two_hop_sponsored_mr n=0');
      return;
    }
    logger.info(
      'witness_two_hop_sponsored_mr n=${summary.n} '
      'p33=${summary.p33} p50=${summary.p50} p75=${summary.p75}',
    );
  }

  Future<void> _logEligibleWitnessCoverage() async {
    final counts = await _telemetry.countEligibleWitnessCoverage();
    logger.info(
      'capability_eligible_witness_coverage '
      'eligible_clearing=${counts.eligibleClearing} '
      'ineligible_only=${counts.ineligibleOnly}',
    );
  }

  Future<void> _logReciprocalAcknowledgementRings() async {
    final counts = await _telemetry.countReciprocalIsolatedAcknowledgementPairs();
    if (counts.count == 0) {
      logger.info('capability_reciprocal_ring_pairs count=0');
      return;
    }
    logger.info(
      'capability_reciprocal_ring_pairs count=${counts.count} '
      'tags_1=${counts.tags1} tags_2=${counts.tags2} '
      'tags_3plus=${counts.tags3plus}',
    );
  }
}

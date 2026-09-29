import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/capability_telemetry_port.dart';

@Injectable(
  as: CapabilityTelemetryPort,
  env: [Environment.test],
  order: 1,
)
class CapabilityTelemetryRepositoryMock implements CapabilityTelemetryPort {
  @override
  Future<({int seedTriples, int renewed})> countSeedRenewal() =>
      Future.value((seedTriples: 0, renewed: 0));

  @override
  Future<({int n, double? p33, double? p50, double? p75})>
  twoHopSponsoredForwardMrPercentiles() =>
      Future.value((n: 0, p33: null, p50: null, p75: null));

  @override
  Future<({int eligibleClearing, int ineligibleOnly})>
  countEligibleWitnessCoverage() =>
      Future.value((eligibleClearing: 0, ineligibleOnly: 0));

  @override
  Future<({int count, int tags1, int tags2, int tags3plus})>
  countReciprocalIsolatedAcknowledgementPairs() =>
      Future.value((count: 0, tags1: 0, tags2: 0, tags3plus: 0));
}

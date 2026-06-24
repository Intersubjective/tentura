/// V2 mutation result: persisted beacon status after coordination change.
class BeaconStatusResult {
  const BeaconStatusResult({
    required this.beaconId,
    required this.status,
    this.statusChangedAt,
  });

  final String beaconId;
  final int status;
  final DateTime? statusChangedAt;
}

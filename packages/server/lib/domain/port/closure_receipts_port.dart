import 'package:injectable/injectable.dart';

abstract interface class ClosureReceiptsPort {
  Future<void> opened(String beaconId, int epoch);

  Future<void> finalized(String beaconId, int epoch);

  Future<void> cancelled(String beaconId, int epoch);
}

/// Placeholder until A17 wires closure receipt outbox writes.
@Singleton(as: ClosureReceiptsPort)
class NoopClosureReceipts implements ClosureReceiptsPort {
  @override
  Future<void> opened(String beaconId, int epoch) async {}

  @override
  Future<void> finalized(String beaconId, int epoch) async {}

  @override
  Future<void> cancelled(String beaconId, int epoch) async {}
}

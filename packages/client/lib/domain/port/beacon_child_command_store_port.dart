import 'package:tentura_root/domain/entity/beacon_creation_context.dart';

/// Persists a child-creation [clientCommandId] across retries and app restart
/// until a canonical server beacon id is recovered (plan §3.4.1).
abstract interface class BeaconChildCommandStorePort {
  Future<String?> read(BeaconCreationContext context);

  Future<void> write(BeaconCreationContext context, String clientCommandId);

  Future<void> clear(BeaconCreationContext context);
}

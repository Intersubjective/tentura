import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';

import 'package:tentura/data/service/local_secure_storage.dart';
import 'package:tentura/domain/port/beacon_child_command_store_port.dart';

@Singleton(as: BeaconChildCommandStorePort, env: [Environment.dev, Environment.prod])
class BeaconChildCommandStore implements BeaconChildCommandStorePort {
  BeaconChildCommandStore(this._storage);

  final LocalSecureStorage _storage;

  static String storageKey(BeaconCreationContext context) => switch (context) {
    BeaconCreationContextStandalone() => throw ArgumentError(
      'Standalone creation has no client command id',
    ),
    BeaconCreationContextChild(:final parentBeaconId) =>
      'beacon_child_cmd:$parentBeaconId',
    BeaconCreationContextPromotedChild(
      :final parentBeaconId,
      :final sourceMessageId,
    ) =>
      'beacon_child_cmd:$parentBeaconId:$sourceMessageId',
  };

  @override
  Future<String?> read(BeaconCreationContext context) =>
      _storage.read(storageKey(context));

  @override
  Future<void> write(
    BeaconCreationContext context,
    String clientCommandId,
  ) => _storage.write(storageKey(context), clientCommandId);

  @override
  Future<void> clear(BeaconCreationContext context) =>
      _storage.delete(storageKey(context));
}

import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';

import 'package:tentura/domain/port/beacon_child_command_store_port.dart';

/// Keeps Request-creation client command ids in ordinary local storage
/// (localStorage on web): they are not secrets.
@Singleton(as: BeaconChildCommandStorePort, env: [Environment.dev, Environment.prod])
class BeaconChildCommandStore implements BeaconChildCommandStorePort {
  final _storage = SharedPreferencesAsync();

  static String storageKey(BeaconCreationContext context) => switch (context) {
    BeaconCreationContextStandalone() => 'beacon_create_op',
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
      _storage.getString(storageKey(context));

  @override
  Future<void> write(
    BeaconCreationContext context,
    String clientCommandId,
  ) => _storage.setString(storageKey(context), clientCommandId);

  @override
  Future<void> clear(BeaconCreationContext context) =>
      _storage.remove(storageKey(context));
}

import 'package:tentura_server/domain/entity/beacon_mute_entity.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';

/// Persistence for account notification preferences and per-beacon mutes.
abstract interface class NotificationPreferenceRepositoryPort {
  /// Returns stored preferences for [accountId], or conservative defaults when
  /// no row exists yet.
  Future<NotificationPreferencesEntity> getForAccount(String accountId);

  /// Batch variant for the digest job; missing accounts map to defaults.
  Future<Map<String, NotificationPreferencesEntity>> getForAccounts(
    Set<String> accountIds,
  );

  Future<void> upsert(NotificationPreferencesEntity prefs);

  Future<List<BeaconMuteEntity>> getBeaconMutes(String accountId);

  /// Convenience for the gate: the set of beacon ids currently muted at [now].
  Future<Set<String>> getMutedBeaconIds(String accountId, DateTime now);

  Future<void> setBeaconMute({
    required String accountId,
    required String beaconId,
    DateTime? mutedUntil,
  });

  Future<void> clearBeaconMute({
    required String accountId,
    required String beaconId,
  });
}

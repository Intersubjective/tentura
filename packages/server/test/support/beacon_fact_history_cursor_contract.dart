import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/beacon_fact_history_entry_entity.dart';

/// Persisted `beacon_activity_event.id` for events in the active test catalog.
/// The repository maps this onto [BeaconFactHistoryEvent] (tentura-1z0).
final catalogActivityEventIds = <BeaconFactHistoryEvent, String>{};

/// Reads [activityEventId] once the entity exposes it (codegen after domain change).
String? persistedActivityEventIdOnEntity(BeaconFactHistoryEvent event) {
  final dynamic raw = event;
  try {
    return raw.activityEventId as String?;
  } on NoSuchMethodError {
    return null;
  }
}

/// SQL / repository `entry_key` for a history row (plan §14.3).
String repositoryHistoryEntryKey(BeaconFactHistoryEntry entry) {
  switch (entry) {
    case BeaconFactHistoryRevision(:final seq):
      return 'r${seq.toString().padLeft(10, '0')}';
    case BeaconFactHistoryEvent e:
      final id = persistedActivityEventIdOnEntity(e) ?? catalogActivityEventIds[e];
      expect(
        id,
        isNotNull,
        reason: 'catalog must model beacon_activity_event.id for events',
      );
      return 'e$id';
  }
}

/// Entry key the case must derive from the entity alone (no test-side map).
String historyEntryKeyFromEntityOnly(BeaconFactHistoryEntry entry) {
  switch (entry) {
    case BeaconFactHistoryRevision(:final seq):
      return 'r${seq.toString().padLeft(10, '0')}';
    case BeaconFactHistoryEvent e:
      final id = persistedActivityEventIdOnEntity(e);
      expect(
        id,
        isNotNull,
        reason:
            'BeaconFactHistoryEvent must carry beacon_activity_event.id for '
            'history cursors (entry_key e||id)',
      );
      return 'e$id';
  }
}

int historyTupleCompare(
  ({DateTime createdAt, String entryKey}) a,
  ({DateTime createdAt, String entryKey}) b,
) {
  final byTime = a.createdAt.toUtc().compareTo(b.createdAt.toUtc());
  return byTime != 0 ? byTime : a.entryKey.compareTo(b.entryKey);
}

({DateTime createdAt, String entryKey}) historySortKey(
  BeaconFactHistoryEntry entry,
) => (
  createdAt: entry.createdAt.toUtc(),
  entryKey: repositoryHistoryEntryKey(entry),
);

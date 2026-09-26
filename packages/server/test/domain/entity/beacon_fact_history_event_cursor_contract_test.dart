import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/entity/beacon_fact_history_entry_entity.dart';

import '../../support/beacon_fact_history_cursor_contract.dart';

/// tentura-1z0: history cursors for event rows use `e||beacon_activity_event.id`;
/// the domain entity must expose that id after repository mapping.
void main() {
  test(
    'BeaconFactHistoryEvent carries persisted activityEventId for e||id cursors',
    () {
      final event = BeaconFactHistoryEntry.event(
        activityEventId: 'Evhist000001',
        type: BeaconActivityEventTypeBits.factVisibilityChanged,
        actorTitle: 'Actor',
        createdAt: DateTime.utc(2026, 3, 1, 12, 2),
      );

      expect(
        persistedActivityEventIdOnEntity(event as BeaconFactHistoryEvent),
        isNotNull,
        reason:
            'repository history() must map beacon_activity_event.id onto the '
            'entity so BeaconFactCardCase can serialise entry_key e||id',
      );
    },
  );
}

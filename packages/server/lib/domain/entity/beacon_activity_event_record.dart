/// Domain projection of a [`beacon_activity_event`] row (V2 / use-case API).
class BeaconActivityEventRecord {
  const BeaconActivityEventRecord({
    required this.id,
    required this.beaconId,
    required this.visibility,
    required this.type,
    required this.createdAt, this.actorId,
    this.diffJson,
  });

  final String id;
  final String beaconId;
  final int visibility;
  final int type;
  final String? actorId;
  final String? diffJson;
  final DateTime createdAt;
}

/// Latest meaningful log event for one beacon on My Work cards.
class MyWorkLastActivityEventRow {
  const MyWorkLastActivityEventRow({
    required this.beaconId,
    this.event,
    this.actorTitle,
    this.actorImageId,
  });

  final String beaconId;
  final BeaconActivityEventRecord? event;
  final String? actorTitle;
  final String? actorImageId;
}

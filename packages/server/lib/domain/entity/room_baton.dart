/// «Who'll take it?» (baton) domain entities — plan §2.2/B2
/// (`docs/plans/baton-who-takes-it-plan.md`).
library;

import 'package:tentura_server/utils/id.dart';

/// Canonical persisted baton status (`beacon_room_baton.status` smallint).
enum BatonStatus {
  collecting(0),
  taken(1),
  cancelled(2);

  const BatonStatus(this.smallintValue);

  final int smallintValue;

  static BatonStatus fromSmallint(int v) => switch (v) {
    0 => BatonStatus.collecting,
    1 => BatonStatus.taken,
    2 => BatonStatus.cancelled,
    _ => throw ArgumentError.value(v, 'v', 'unknown BatonStatus'),
  };
}

/// Canonical persisted candidate response
/// (`beacon_room_baton_candidate.response` smallint).
enum BatonResponse {
  waiting(0),
  canHelp(1),
  cantHelp(2);

  const BatonResponse(this.smallintValue);

  final int smallintValue;

  static BatonResponse fromSmallint(int v) => switch (v) {
    0 => BatonResponse.waiting,
    1 => BatonResponse.canHelp,
    2 => BatonResponse.cantHelp,
    _ => throw ArgumentError.value(v, 'v', 'unknown BatonResponse'),
  };
}

/// How the taker was decided (`beacon_room_baton.selection_mode` smallint).
enum BatonSelectionMode {
  auto(1),
  manual(2);

  const BatonSelectionMode(this.smallintValue);

  final int smallintValue;

  static BatonSelectionMode fromSmallint(int v) => switch (v) {
    1 => BatonSelectionMode.auto,
    2 => BatonSelectionMode.manual,
    _ => throw ArgumentError.value(v, 'v', 'unknown BatonSelectionMode'),
  };
}

class RoomBaton {
  static String get newId => generateId('L');

  const RoomBaton({
    required this.id,
    required this.messageId,
    required this.beaconId,
    required this.authorId,
    required this.status,
    required this.createdAt,
    this.takerId,
    this.selectionMode,
    this.allAnsweredNotifiedAt,
    this.resolvedAt,
  });

  final String id;
  final String messageId;
  final String beaconId;
  final String authorId;
  final BatonStatus status;
  final String? takerId;
  final BatonSelectionMode? selectionMode;
  final DateTime? allAnsweredNotifiedAt;
  final DateTime createdAt;
  final DateTime? resolvedAt;
}

class RoomBatonCandidate {
  const RoomBatonCandidate({
    required this.batonId,
    required this.userId,
    required this.tier,
    required this.response,
    this.respondedAt,
  });

  final String batonId;
  final String userId;
  final int tier;
  final BatonResponse response;
  final DateTime? respondedAt;
}

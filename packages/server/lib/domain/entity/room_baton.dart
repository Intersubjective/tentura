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

  /// Wire name in the room message `batonData` payload.
  String get wireName => name;

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

  /// Wire name in the room message `batonData` payload.
  String get wireName => switch (this) {
    BatonResponse.waiting => 'waiting',
    BatonResponse.canHelp => 'can_help',
    BatonResponse.cantHelp => 'cant_help',
  };

  static BatonResponse fromSmallint(int v) => switch (v) {
    0 => BatonResponse.waiting,
    1 => BatonResponse.canHelp,
    2 => BatonResponse.cantHelp,
    _ => throw ArgumentError.value(v, 'v', 'unknown BatonResponse'),
  };
}

/// Canonical persisted partner answer
/// (`beacon_room_baton_candidate.partner_response` smallint): whether the
/// person a candidate named agreed to take it on together.
enum BatonPartnerResponse {
  pending(0),
  accepted(1),
  declined(2);

  const BatonPartnerResponse(this.smallintValue);

  final int smallintValue;

  static BatonPartnerResponse fromSmallint(int v) => switch (v) {
    0 => BatonPartnerResponse.pending,
    1 => BatonPartnerResponse.accepted,
    2 => BatonPartnerResponse.declined,
    _ => throw ArgumentError.value(v, 'v', 'unknown BatonPartnerResponse'),
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
    this.coTakerId,
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
  final String? coTakerId;
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
    this.partnerUserId,
    this.partnerResponse,
    this.partnerRespondedAt,
    this.partnerInvites = 0,
  });

  final String batonId;
  final String userId;
  final int tier;
  final BatonResponse response;
  final DateTime? respondedAt;

  /// The person this candidate asked to take it on together, if any.
  final String? partnerUserId;
  final BatonPartnerResponse? partnerResponse;
  final DateTime? partnerRespondedAt;

  /// Distinct partners this candidate has named on this baton.
  final int partnerInvites;
}

import 'package:meta/meta.dart';

import 'package:tentura_server/utils/id.dart';

import 'commitment_event_kind.dart';

@immutable
class CommitmentEvent {
  const CommitmentEvent({
    required this.id,
    required this.seq,
    required this.beaconId,
    required this.userId,
    required this.actorUserId,
    required this.kind,
    required this.createdAt,
    this.reason,
  });

  static String get newId => generateId('CE');

  final String id;
  final int seq;
  final String beaconId;
  final String userId;
  final String actorUserId;
  final CommitmentEventKind kind;
  final String? reason;
  final DateTime createdAt;
}

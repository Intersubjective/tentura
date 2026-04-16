import 'package:meta/meta.dart';

import 'user_public_record.dart';

/// One beacon commitment with optional author coordination fields (V2).
@immutable
class CommitmentWithCoordinationRow {
  const CommitmentWithCoordinationRow({
    required this.beaconId,
    required this.userId,
    required this.message,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.user,
    this.helpType,
    this.uncommitReason,
    this.responseType,
    this.responseUpdatedAt,
    this.responseAuthorUserId,
  });

  final String beaconId;
  final String userId;
  final String message;
  final String? helpType;
  final int status;
  final String? uncommitReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? responseType;
  final DateTime? responseUpdatedAt;
  final String? responseAuthorUserId;
  final UserPublicRecord user;
}

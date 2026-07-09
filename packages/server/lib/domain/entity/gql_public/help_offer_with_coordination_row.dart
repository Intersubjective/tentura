import 'package:meta/meta.dart';

import 'user_public_record.dart';

/// One beacon help offer with optional author coordination fields (V2).
@immutable
class HelpOfferWithCoordinationRow {
  const HelpOfferWithCoordinationRow({
    required this.beaconId,
    required this.userId,
    required this.message,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.user,
    this.helpType,
    this.withdrawReason,
    this.responseType,
    this.responseUpdatedAt,
    this.responseAuthorUserId,
    this.roomAccess,
    this.admissionAction,
    this.lastDeclineReason,
    this.lastRemoveReason,
  });

  final String beaconId;
  final String userId;
  final String message;
  final String? helpType;
  final int status;
  final String? withdrawReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? responseType;
  final DateTime? responseUpdatedAt;
  final String? responseAuthorUserId;

  /// `beacon_participants.room_access` for this help offerer, if any row exists.
  final int? roomAccess;
  final int? admissionAction;
  final String? lastDeclineReason;
  final String? lastRemoveReason;
  final UserPublicRecord user;

  HelpOfferWithCoordinationRow copyWith({
    int? admissionAction,
    String? lastDeclineReason,
    String? lastRemoveReason,
    bool clearAdmissionFields = false,
  }) => HelpOfferWithCoordinationRow(
    beaconId: beaconId,
    userId: userId,
    message: message,
    status: status,
    createdAt: createdAt,
    updatedAt: updatedAt,
    user: user,
    helpType: helpType,
    withdrawReason: withdrawReason,
    responseType: responseType,
    responseUpdatedAt: responseUpdatedAt,
    responseAuthorUserId: responseAuthorUserId,
    roomAccess: roomAccess,
    admissionAction: clearAdmissionFields
        ? null
        : admissionAction ?? this.admissionAction,
    lastDeclineReason: clearAdmissionFields
        ? null
        : lastDeclineReason ?? this.lastDeclineReason,
    lastRemoveReason: clearAdmissionFields
        ? null
        : lastRemoveReason ?? this.lastRemoveReason,
  );
}

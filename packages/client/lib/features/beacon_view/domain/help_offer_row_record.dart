import 'package:tentura/domain/entity/profile.dart';

/// One help-offer row as the coordination API returns it (People tab input).
typedef HelpOfferRowRecord = ({
  String beaconId,
  String userId,
  Profile user,
  String message,
  String? helpType,
  String? roleLabel,
  int status,
  String? withdrawReason,
  DateTime createdAt,
  DateTime updatedAt,
  int? responseType,
  DateTime? responseUpdatedAt,
  String? responseAuthorUserId,
  int? roomAccess,
  int? admissionAction,
  String? lastDeclineReason,
  String? lastRemoveReason,
  int stakeState,
  int offerKind,
  bool isDirectAuthorForward,
  String? authorSeenAt,
});

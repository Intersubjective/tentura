import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';

part 'beacon_people_row.freezed.dart';

/// Minimal help-offer fields for People-tab bucketing (domain layer).
class BeaconPeopleHelpOfferInput {
  const BeaconPeopleHelpOfferInput({
    required this.userId,
    required this.profile,
    required this.isWithdrawn,
    this.roomAccess,
    this.coordinationResponse,
  });

  final String userId;
  final Profile profile;
  final bool isWithdrawn;
  final int? roomAccess;
  final CoordinationResponseType? coordinationResponse;
}

@freezed
abstract class BeaconPeopleRow with _$BeaconPeopleRow {
  const factory BeaconPeopleRow({
    required String userId,
    required Profile profile,
    BeaconParticipant? participant,
    @Default(false) bool isAuthor,
  }) = _BeaconPeopleRow;
}

@freezed
abstract class BeaconPeopleSections with _$BeaconPeopleSections {
  const factory BeaconPeopleSections({
    @Default([]) List<BeaconPeopleRow> activeHelpers,
    @Default([]) List<BeaconPeopleRow> willingToHelp,
    @Default([]) List<BeaconPeopleRow> notFitting,
  }) = _BeaconPeopleSections;
}

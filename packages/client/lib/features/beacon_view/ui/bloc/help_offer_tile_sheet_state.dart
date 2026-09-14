part of 'help_offer_tile_sheet_cubit.dart';

@freezed
abstract class HelpOfferTileSheetState extends StateBase
    with _$HelpOfferTileSheetState {
  const factory HelpOfferTileSheetState({
    required String beaconId,
    required String offerUserId,
    required Profile myProfile,
    required Beacon beacon,
    @Default(StateIsLoading()) StateStatus status,
    TimelineHelpOffer? offer,
    BeaconParticipant? participant,
    @Default([]) List<BeaconParticipant> roomParticipants,
    Object? loadError,
  }) = _HelpOfferTileSheetState;

  const HelpOfferTileSheetState._();

  bool get isBeaconMine => beacon.author.id == myProfile.id;

  bool get isSteward => roomParticipants.any(
    (p) =>
        p.userId == myProfile.id &&
        p.role == BeaconParticipantRoleBits.steward &&
        p.roomAccess == RoomAccessBits.admitted,
  );

  bool get isAuthorOrSteward => isBeaconMine || isSteward;

  bool get isLoaded => isSuccess && loadError == null;
}

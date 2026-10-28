import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/beacon_lobby.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'beacon_lobby_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class BeaconLobbyState extends StateBase with _$BeaconLobbyState {
  const factory BeaconLobbyState({
    @Default(StateIsLoading()) StateStatus status,
    BeaconLobbyInfo? info,

    /// The server said this viewer may not use Questions.
    @Default(false) bool unavailable,

    /// Why, when the server can say (the author removed the viewer).
    BeaconLobbyLimitReason? unavailableReason,

    /// The first load failed for another reason (offline, server error):
    /// the screen offers a retry, not the access message.
    Object? loadError,
  }) = _BeaconLobbyState;

  const BeaconLobbyState._();

  bool get isAuthor => info?.isAuthor ?? false;

  bool get canPost => info?.canPost ?? false;

  /// The Request author (their answers are marked); '' until opened.
  String get authorId => info?.authorId ?? '';

  BeaconLobbyLimitReason? get readOnlyReason => info?.readOnlyReason;

  /// Inside already (offered, admitted, steward), not the author (#657).
  bool get isHelper => info?.isHelper ?? false;

  /// The Request no longer takes help offers (Final check or closed), so
  /// nobody is told to ask or offer (#657).
  bool get closedToOffers =>
      !(info?.takesOffers ?? true) ||
      readOnlyReason == BeaconLobbyLimitReason.closed;

  List<BeaconLobbyBannedPerson> get banned => info?.banned ?? const [];

  bool isBanned(String userId) => banned.any((b) => b.userId == userId);
}

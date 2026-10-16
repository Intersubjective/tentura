import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/beacon_lobby.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'beacon_lobby_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class BeaconLobbyState extends StateBase with _$BeaconLobbyState {
  const factory BeaconLobbyState({
    @Default(StateIsLoading()) StateStatus status,
    BeaconLobbyInfo? info,
    @Default([]) List<BeaconLobbyMessage> messages,
    @Default(false) bool sending,

    /// Counts accepted posts; the composer clears when it grows.
    @Default(0) int postedCount,

    /// The server said this viewer may not use the lobby.
    @Default(false) bool unavailable,

    /// The first load failed for another reason (offline, server error):
    /// the screen offers a retry, not the access message.
    Object? loadError,
  }) = _BeaconLobbyState;

  const BeaconLobbyState._();

  bool get isAuthor => info?.isAuthor ?? false;

  bool get canPost => info?.canPost ?? false;

  List<String> get bannedUserIds => info?.bannedUserIds ?? const [];
}

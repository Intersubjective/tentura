import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/beacon_lobby_gateway.dart';
import '../../domain/entity/beacon_lobby.dart';

enum BeaconLobbyStatus { loading, ready, unavailable }

class BeaconLobbyState {
  const BeaconLobbyState({
    this.status = BeaconLobbyStatus.loading,
    this.info,
    this.messages = const [],
    this.sending = false,
    this.actionFailed = false,
  });

  final BeaconLobbyStatus status;
  final BeaconLobbyInfo? info;
  final List<BeaconLobbyMessage> messages;
  final bool sending;

  /// The last post / ban / unban failed (the screen shows a short notice).
  final bool actionFailed;

  bool get isAuthor => info?.isAuthor ?? false;
  List<String> get bannedUserIds => info?.bannedUserIds ?? const [];

  BeaconLobbyState copyWith({
    BeaconLobbyStatus? status,
    BeaconLobbyInfo? info,
    List<BeaconLobbyMessage>? messages,
    bool? sending,
    bool? actionFailed,
  }) => BeaconLobbyState(
    status: status ?? this.status,
    info: info ?? this.info,
    messages: messages ?? this.messages,
    sending: sending ?? this.sending,
    actionFailed: actionFailed ?? this.actionFailed,
  );
}

/// U088 — the Request lobby: load, post, and (author) ban / let back in.
///
/// Lobby messages are not pushed to people outside the main discussion, so
/// the open screen refreshes every [pollInterval].
class BeaconLobbyCubit extends Cubit<BeaconLobbyState> {
  BeaconLobbyCubit({
    required this.beaconId,
    required BeaconLobbyGateway gateway,
    this.pollInterval = const Duration(seconds: 20),
  }) : _gateway = gateway,
       super(const BeaconLobbyState());

  final String beaconId;
  final Duration pollInterval;
  final BeaconLobbyGateway _gateway;
  Timer? _poll;

  Future<void> load() async {
    try {
      final info = await _gateway.open(beaconId);
      final messages = await _gateway.messages(
        beaconId: beaconId,
        lobbyId: info.lobbyId,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          status: BeaconLobbyStatus.ready,
          info: info,
          messages: messages,
        ),
      );
      _poll ??= Timer.periodic(pollInterval, (_) => unawaited(refresh()));
    } catch (_) {
      if (isClosed) return;
      _poll?.cancel();
      _poll = null;
      emit(
        BeaconLobbyState(
          status: BeaconLobbyStatus.unavailable,
          info: state.info,
        ),
      );
    }
  }

  /// Re-reads the lobby; a ban that happened meanwhile ends in unavailable.
  Future<void> refresh() => load();

  Future<bool> post(String text) async {
    final body = text.trim();
    final info = state.info;
    if (body.isEmpty || info == null || state.sending) return false;
    emit(state.copyWith(sending: true, actionFailed: false));
    try {
      await _gateway.post(beaconId: beaconId, lobbyId: info.lobbyId, body: body);
      final messages = await _gateway.messages(
        beaconId: beaconId,
        lobbyId: info.lobbyId,
      );
      if (isClosed) return true;
      emit(state.copyWith(sending: false, messages: messages));
      return true;
    } catch (_) {
      if (isClosed) return false;
      emit(state.copyWith(sending: false, actionFailed: true));
      return false;
    }
  }

  Future<void> ban(String userId) => _authorAction(
    () => _gateway.ban(beaconId: beaconId, userId: userId),
  );

  Future<void> unban(String userId) => _authorAction(
    () => _gateway.unban(beaconId: beaconId, userId: userId),
  );

  Future<void> _authorAction(Future<void> Function() run) async {
    if (!state.isAuthor) return;
    emit(state.copyWith(actionFailed: false));
    try {
      await run();
      await load();
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(actionFailed: true));
    }
  }

  @override
  Future<void> close() {
    _poll?.cancel();
    return super.close();
  }
}

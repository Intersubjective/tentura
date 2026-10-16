import 'dart:async';

import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../domain/exception/beacon_lobby_exception.dart';
import '../../domain/use_case/beacon_lobby_case.dart';
import 'beacon_lobby_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'beacon_lobby_state.dart';

/// U088 — the Request lobby: load, post, and (author) remove / let back in.
///
/// No polling: the lobby refetches on the Request's realtime hints and
/// catch-ups, after the viewer's own actions, and on pull-to-refresh.
class BeaconLobbyCubit extends Cubit<BeaconLobbyState> {
  BeaconLobbyCubit(
    this._case,
    this._effects, {
    required this.beaconId,
  }) : super(const BeaconLobbyState()) {
    _changes = _case
        .lobbyChanges(beaconId)
        .listen((_) => unawaited(_refresh()));
  }

  final String beaconId;

  final BeaconLobbyCase _case;

  final UiEffectPort _effects;

  late final StreamSubscription<void> _changes;

  bool _refreshing = false;

  bool _refreshAgain = false;

  /// First load, and the retry after a failed one.
  Future<void> load() async {
    emit(
      state.copyWith(
        status: StateStatus.isLoading,
        unavailable: false,
        loadError: null,
      ),
    );
    try {
      await _fetch();
    } on BeaconLobbyUnavailableException {
      _showUnavailable();
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(status: StateStatus.isSuccess, loadError: e));
    }
  }

  /// Pull-to-refresh: a failure is shown, the lobby stays as it was.
  Future<void> refresh() => _refresh(userInitiated: true);

  Future<void> post(String text) async {
    final body = text.trim();
    final info = state.info;
    if (body.isEmpty || info == null || !info.canPost || state.sending) {
      return;
    }
    emit(state.copyWith(sending: true));
    try {
      await _case.post(beaconId: beaconId, lobbyId: info.lobbyId, body: body);
      if (isClosed) return;
      emit(state.copyWith(sending: false, postedCount: state.postedCount + 1));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(sending: false));
      _effects.emit(ShowError(e));
      return;
    }
    await _refresh();
  }

  Future<void> ban(String userId) => _authorAction(
    () => _case.ban(beaconId: beaconId, userId: userId),
  );

  Future<void> unban(String userId) => _authorAction(
    () => _case.unban(beaconId: beaconId, userId: userId),
  );

  Future<void> _authorAction(Future<void> Function() run) async {
    if (!state.isAuthor) return;
    try {
      await run();
    } catch (e) {
      if (!isClosed) _effects.emit(ShowError(e));
      return;
    }
    await _refresh();
  }

  /// Coalesces overlapping refreshes into one more round.
  Future<void> _refresh({bool userInitiated = false}) async {
    if (state.info == null && !state.unavailable) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        try {
          await _fetch();
        } on BeaconLobbyUnavailableException {
          _showUnavailable();
        } catch (e) {
          // A background refresh keeps what is on screen; the next hint or a
          // pull retries.
          if (userInitiated && !isClosed) _effects.emit(ShowError(e));
        }
      } while (_refreshAgain && !isClosed);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _fetch() async {
    final info = await _case.open(beaconId);
    final messages = await _case.messages(
      beaconId: beaconId,
      lobbyId: info.lobbyId,
    );
    if (isClosed) return;
    emit(
      state.copyWith(
        status: StateStatus.isSuccess,
        info: info,
        messages: messages,
        unavailable: false,
        loadError: null,
      ),
    );
  }

  /// Removed meanwhile (or never allowed): nothing of the lobby stays shown.
  void _showUnavailable() {
    if (isClosed) return;
    emit(
      state.copyWith(
        status: StateStatus.isSuccess,
        info: null,
        messages: const [],
        unavailable: true,
        loadError: null,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}

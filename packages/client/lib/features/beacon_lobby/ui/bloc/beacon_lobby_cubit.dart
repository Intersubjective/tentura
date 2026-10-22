import 'dart:async';

import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../domain/entity/beacon_lobby.dart';
import '../../domain/exception/beacon_lobby_exception.dart';
import '../../domain/use_case/beacon_lobby_case.dart';
import 'beacon_lobby_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'beacon_lobby_state.dart';

/// Request Questions (internally the lobby, U088): load, page back, post,
/// and (author) remove / let back in.
///
/// No polling. A message hint for the Request refetches only the newest
/// page (no access re-check); an offer / forward / admission / status hint
/// or a realtime catch-up re-opens (the viewer's standing may have changed).
class BeaconLobbyCubit extends Cubit<BeaconLobbyState> {
  BeaconLobbyCubit(
    this._case,
    this._effects, {
    required this.beaconId,
  }) : super(const BeaconLobbyState()) {
    _subscriptions = [
      _case
          .messageChanges(beaconId)
          .listen((_) => unawaited(_refresh(reopen: false))),
      _case
          .accessChanges(beaconId)
          .listen((_) => unawaited(_refresh(reopen: true))),
    ];
  }

  /// Server page size of `RoomMessageList`.
  static const pageSize = 50;

  final String beaconId;

  final BeaconLobbyCase _case;

  final UiEffectPort _effects;

  late final List<StreamSubscription<void>> _subscriptions;

  bool _refreshing = false;

  bool _refreshAgain = false;

  bool _reopenAgain = false;

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
      await _fetch(reopen: true);
    } on BeaconLobbyUnavailableException {
      _showUnavailable();
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(status: StateStatus.isSuccess, loadError: e));
    }
  }

  /// Pull-to-refresh: a failure is shown, the thread stays as it was.
  Future<void> refresh() => _refresh(reopen: true, userInitiated: true);

  /// Loads the page before the oldest message shown.
  Future<void> loadOlder() async {
    final info = state.info;
    final oldest = state.messages.isEmpty
        ? null
        : state.messages.first.createdAt;
    if (info == null || oldest == null || state.loadingOlder) return;
    emit(state.copyWith(loadingOlder: true));
    try {
      final page = await _case.messages(
        beaconId: beaconId,
        lobbyId: info.lobbyId,
        before: oldest,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          messages: _merge(page, state.messages),
          hasOlder: page.length >= pageSize,
          loadingOlder: false,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(loadingOlder: false));
      _effects.emit(ShowError(e));
    }
  }

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
    await _refresh(reopen: false);
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
    await _refresh(reopen: true);
  }

  /// Coalesces overlapping refreshes into one more round (re-opening if any
  /// of the coalesced requests asked for it).
  Future<void> _refresh({
    required bool reopen,
    bool userInitiated = false,
  }) async {
    if (state.info == null && !state.unavailable) return;
    if (_refreshing) {
      _refreshAgain = true;
      _reopenAgain = _reopenAgain || reopen;
      return;
    }
    _refreshing = true;
    var nextReopen = reopen || state.info == null;
    try {
      do {
        _refreshAgain = false;
        _reopenAgain = false;
        try {
          await _fetch(reopen: nextReopen);
        } on BeaconLobbyUnavailableException {
          _showUnavailable();
        } catch (e) {
          // A background refresh keeps what is on screen; the next hint or a
          // pull retries.
          if (userInitiated && !isClosed) _effects.emit(ShowError(e));
        }
        nextReopen = _reopenAgain || state.info == null;
      } while (_refreshAgain && !isClosed);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _fetch({required bool reopen}) async {
    final current = state.info;
    final info = reopen || current == null
        ? await _case.open(beaconId)
        : current;
    final newest = await _case.messages(
      beaconId: beaconId,
      lobbyId: info.lobbyId,
    );
    if (isClosed) return;
    // Keep the older pages already loaded; the newest page replaces its own
    // time range (an edit or delete there shows up).
    final firstLoad = current == null;
    final cutoff = newest.isEmpty ? null : newest.first.createdAt;
    final kept = firstLoad || newest.length < pageSize || cutoff == null
        ? const <BeaconLobbyMessage>[]
        : [
            for (final m in state.messages)
              if (m.createdAt != null && m.createdAt!.isBefore(cutoff)) m,
          ];
    emit(
      state.copyWith(
        status: StateStatus.isSuccess,
        info: info,
        messages: _merge(kept, newest),
        hasOlder: firstLoad
            ? newest.length >= pageSize
            : (kept.isNotEmpty ? state.hasOlder : newest.length >= pageSize),
        unavailable: false,
        loadError: null,
      ),
    );
    unawaited(_markSeen(info.lobbyId));
  }

  /// Settles this thread's attention items; a failure is harmless (the next
  /// open retries).
  Future<void> _markSeen(String lobbyId) async {
    try {
      await _case.markSeen(beaconId: beaconId, lobbyId: lobbyId);
    } catch (_) {}
  }

  static List<BeaconLobbyMessage> _merge(
    List<BeaconLobbyMessage> a,
    List<BeaconLobbyMessage> b,
  ) {
    final byId = <String, BeaconLobbyMessage>{
      for (final m in a) m.id: m,
      for (final m in b) m.id: m,
    };
    final out = byId.values.toList()
      ..sort((x, y) {
        final xt = x.createdAt;
        final yt = y.createdAt;
        if (xt == null || yt == null) return 0;
        return xt.compareTo(yt);
      });
    return out;
  }

  /// Removed meanwhile (or never allowed): nothing of the thread stays shown.
  void _showUnavailable() {
    if (isClosed) return;
    emit(
      state.copyWith(
        status: StateStatus.isSuccess,
        info: null,
        messages: const [],
        hasOlder: false,
        unavailable: true,
        loadError: null,
      ),
    );
  }

  @override
  Future<void> close() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    return super.close();
  }
}

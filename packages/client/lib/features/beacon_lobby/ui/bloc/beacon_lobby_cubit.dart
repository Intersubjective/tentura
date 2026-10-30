import 'dart:async';

import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../domain/entity/beacon_lobby.dart';
import '../../domain/exception/beacon_lobby_exception.dart';
import '../../domain/use_case/beacon_lobby_case.dart';
import 'beacon_lobby_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'beacon_lobby_state.dart';

/// Request Questions (internally the lobby, U088): the viewer's standing
/// (may they post, and why not), and (author) remove / let back in. The
/// messages are the room chat's on the Questions thread (#726).
///
/// No polling. An offer / forward / admission / status hint or a realtime
/// catch-up re-opens (the viewer's standing may have changed).
class BeaconLobbyCubit extends Cubit<BeaconLobbyState> {
  BeaconLobbyCubit(
    this._case,
    this._effects, {
    required this.beaconId,
    this._attention,
  }) : super(const BeaconLobbyState()) {
    _accessChanges = _case
        .accessChanges(beaconId)
        .listen((_) => unawaited(_refresh()));
  }

  static final _logger = Logger('BeaconLobbyCubit');

  final String beaconId;

  final BeaconLobbyCase _case;

  final UiEffectPort _effects;

  final AttentionCase? _attention;

  late final StreamSubscription<void> _accessChanges;

  bool _refreshing = false;

  bool _refreshAgain = false;

  /// The same persisted Questions unread state used by the Overview entry.
  Future<BeaconLobbyAccess> loadAccess() => _case.access(beaconId);

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
      await _open();
      unawaited(_clearQuestionsUpdates());
    } on BeaconLobbyUnavailableException {
      _showUnavailable();
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(status: StateStatus.isSuccess, loadError: e));
    }
  }

  /// Questions is on screen, so the unread messages it holds count as read:
  /// the Request-open clear leaves them alone, this is where they are cleared.
  Future<void> _clearQuestionsUpdates() async {
    final attention = _attention;
    if (attention == null) return;
    try {
      String? previousId;
      while (!isClosed) {
        final rows = await attention.myWorkAttention({beaconId});
        final latest = rows.isEmpty ? null : rows.first.latestUnseen;
        if (latest == null ||
            latest.id == previousId ||
            !isQuestionsAttentionReceipt(latest)) {
          return;
        }
        previousId = latest.id;
        await attention.clearReceipt(receiptId: latest.id);
      }
    } on Object catch (error, stackTrace) {
      // A failed clear is not a failed open: Questions is already on screen.
      _logger.warning('Questions-open clear failed', error, stackTrace);
    }
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

  /// Coalesces overlapping re-opens into one more round. A failed background
  /// re-open keeps what is on screen; the next hint retries.
  Future<void> _refresh() async {
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
          await _open();
        } on BeaconLobbyUnavailableException {
          _showUnavailable();
        } catch (_) {}
      } while (_refreshAgain && !isClosed);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _open() async {
    final info = await _case.open(beaconId);
    if (isClosed) return;
    emit(
      state.copyWith(
        status: StateStatus.isSuccess,
        info: info,
        unavailable: false,
        unavailableReason: null,
        loadError: null,
      ),
    );
  }

  /// Removed meanwhile (or never allowed): nothing of the thread stays shown.
  void _showUnavailable() {
    if (isClosed) return;
    emit(
      state.copyWith(
        status: StateStatus.isSuccess,
        info: null,
        unavailable: true,
        loadError: null,
      ),
    );
    unawaited(_loadUnavailableReason());
  }

  /// Asks the probe why (#657: "the author removed you" reads differently
  /// from "this is for the people it was sent to"). A failure keeps the
  /// generic message.
  Future<void> _loadUnavailableReason() async {
    try {
      final access = await _case.access(beaconId);
      if (isClosed || !state.unavailable) return;
      emit(state.copyWith(unavailableReason: access.limitReason));
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    await _accessChanges.cancel();
    return super.close();
  }
}

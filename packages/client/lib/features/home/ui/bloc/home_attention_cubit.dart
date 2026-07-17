import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';

import 'home_attention_state.dart';

export 'home_attention_state.dart';

/// Adapts semantic unread attention to the currently loaded home projections.
///
/// Inbox/My Work membership remains presentation state. This cubit never sends
/// a surface label to the domain or server: it queries unread candidate ids,
/// then intersects them locally. Unknown or failed projections suppress all
/// markers so stale UI state cannot manufacture activity.
@singleton
final class HomeAttentionCubit extends Cubit<HomeAttentionState> {
  HomeAttentionCubit(this._attention, this._account, this._logger)
    : super(const HomeAttentionState()) {
    _accountSub = _account.currentAccountChanges.listen(_onAccountChanged);
    _attentionSub = _attention.feedPages.listen((_) => _invalidateMarkers());
  }

  static const _maxIdsPerRequest = 500;

  final AttentionCase _attention;
  final AttentionAccountPort _account;
  final Logger _logger;

  late final StreamSubscription<String> _accountSub;
  late final StreamSubscription<Object?> _attentionSub;

  String _accountId = '';
  int _accountGeneration = 0;
  int _projectionGeneration = 0;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;

  void setActiveHomeTab(HomeTab tab) {
    if (state.activeHomeTab == tab) return;
    emit(state.copyWith(activeHomeTab: tab));
  }

  void reportInboxSnapshot({
    required String accountId,
    required Set<String> beaconIds,
    required bool loaded,
  }) {
    if (accountId.isEmpty || accountId != _accountId) return;
    final ids = loaded ? _validIds(beaconIds) : const <String>{};
    if (state.inboxLoaded == loaded && setEquals(state.inboxBeaconIds, ids)) {
      return;
    }
    _projectionGeneration++;
    emit(
      state.copyWith(
        inboxBeaconIds: ids,
        inboxLoaded: loaded,
        unreadBeaconIds: const {},
        markerQueryComplete: false,
      ),
    );
    unawaited(_refreshMarkers());
  }

  void reportMyWorkSnapshot({
    required String accountId,
    required Set<String> beaconIds,
    required bool loaded,
  }) {
    if (accountId.isEmpty || accountId != _accountId) return;
    final ids = loaded ? _validIds(beaconIds) : const <String>{};
    if (state.myWorkLoaded == loaded && setEquals(state.myWorkBeaconIds, ids)) {
      return;
    }
    _projectionGeneration++;
    emit(
      state.copyWith(
        myWorkBeaconIds: ids,
        myWorkLoaded: loaded,
        unreadBeaconIds: const {},
        markerQueryComplete: false,
      ),
    );
    unawaited(_refreshMarkers());
  }

  void _onAccountChanged(String accountId) {
    if (accountId == _accountId) return;
    _accountId = accountId;
    _accountGeneration++;
    _projectionGeneration++;
    _refreshQueued = false;
    emit(HomeAttentionState(activeHomeTab: state.activeHomeTab));
  }

  void _invalidateMarkers() {
    _projectionGeneration++;
    if (state.unreadBeaconIds.isNotEmpty || state.markerQueryComplete) {
      emit(
        state.copyWith(
          unreadBeaconIds: const {},
          markerQueryComplete: false,
        ),
      );
    }
    unawaited(_refreshMarkers());
  }

  Future<void> _refreshMarkers() async {
    if (_accountId.isEmpty || !state.inboxLoaded || !state.myWorkLoaded) {
      return;
    }
    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }

    final candidates = {
      ...state.inboxBeaconIds,
      ...state.myWorkBeaconIds,
    };
    if (candidates.isEmpty) {
      emit(
        state.copyWith(
          unreadBeaconIds: const {},
          markerQueryComplete: true,
        ),
      );
      return;
    }

    _refreshInFlight = true;
    final accountGeneration = _accountGeneration;
    final projectionGeneration = _projectionGeneration;
    try {
      final unread = <String>{};
      final ids = candidates.toList(growable: false);
      for (var offset = 0; offset < ids.length; offset += _maxIdsPerRequest) {
        final nextOffset = offset + _maxIdsPerRequest;
        final end = nextOffset < ids.length ? nextOffset : ids.length;
        unread.addAll(
          await _attention.unreadForBeacons(ids.sublist(offset, end).toSet()),
        );
      }
      if (isClosed ||
          accountGeneration != _accountGeneration ||
          projectionGeneration != _projectionGeneration) {
        return;
      }
      emit(
        state.copyWith(
          unreadBeaconIds: unread.intersection(candidates),
          markerQueryComplete: true,
        ),
      );
    } catch (error, stackTrace) {
      if (!isClosed &&
          accountGeneration == _accountGeneration &&
          projectionGeneration == _projectionGeneration) {
        emit(
          state.copyWith(
            unreadBeaconIds: const {},
            markerQueryComplete: false,
          ),
        );
        _logger.warning(
          'Home attention marker refresh failed',
          error,
          stackTrace,
        );
      }
    } finally {
      _refreshInFlight = false;
      if (_refreshQueued && !isClosed) {
        _refreshQueued = false;
        unawaited(_refreshMarkers());
      }
    }
  }

  static Set<String> _validIds(Set<String> ids) => {
    for (final id in ids)
      if (id.isNotEmpty) id,
  };

  @override
  @disposeMethod
  Future<void> close() async {
    await _accountSub.cancel();
    await _attentionSub.cancel();
    return super.close();
  }
}

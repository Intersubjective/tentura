import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/friends/domain/use_case/friends_case.dart';

import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'friends_state.dart';

export 'friends_state.dart';

/// Global Cubit
@singleton
class FriendsCubit extends Cubit<FriendsState> {
  FriendsCubit(
    this._case,
    this._effects,
  ) : super(const FriendsState(friends: {})) {
    _authChanges = _case.accountChanges.listen(
      _onAuthChanged,
      cancelOnError: false,
    );
    _friendsChanges = _case.localFriendChanges.listen(
      _onFriendsChanged,
      cancelOnError: false,
    );
    _contactChanges = _case.contactChanges.listen(
      (_) => _onContactNamesChanged(),
      cancelOnError: false,
    );
    _projectionChanges = _case.projectionChanges.listen(
      (_) => _scheduleSilentFetch(),
      cancelOnError: false,
    );
  }

  final FriendsCase _case;

  final UiEffectPort _effects;

  late final StreamSubscription<String> _authChanges;

  late final StreamSubscription<Profile> _friendsChanges;

  late final StreamSubscription<void> _contactChanges;
  late final StreamSubscription<void> _projectionChanges;

  static const _refreshDebounce = Duration(milliseconds: 100);
  Timer? _refreshTimer;
  int _fetchSequence = 0;
  bool _hasLoaded = false;

  @override
  @disposeMethod
  Future<void> close() async {
    _refreshTimer?.cancel();
    _case.unwatchPresence();
    await _authChanges.cancel();
    await _friendsChanges.cancel();
    await _contactChanges.cancel();
    await _projectionChanges.cancel();
    return super.close();
  }

  Future<void> fetch({
    bool showLoading = true,
    bool showError = true,
  }) async {
    final sequence = ++_fetchSequence;
    if (showLoading) {
      emit(state.copyWith(status: StateStatus.isLoading));
    }
    try {
      final snapshot = await _case.load();
      if (isClosed || sequence != _fetchSequence) return;
      emit(
        FriendsState(
          friends: snapshot.friends,
          friendContexts: snapshot.friendContexts,
        ),
      );
      _hasLoaded = true;
      _case.watchPresence(snapshot.friends.keys.toSet());
    } catch (e) {
      if (isClosed || sequence != _fetchSequence) return;
      if (!_hasLoaded) {
        emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
      } else if (showError) {
        _effects.emit(ShowError(e));
        emit(state.copyWith(loadError: null, status: const StateIsSuccess()));
      }
    }
  }

  Future<void> addFriend(Profile user) => _case.addFriend(user);

  Future<void> removeFriend(Profile user) => _case.removeFriend(user);

  Future<void> acceptInvitation(String id) => _case.acceptInvitation(id);

  void _onAuthChanged(String userId) {
    _refreshTimer?.cancel();
    _case.unwatchPresence();
    _fetchSequence++;
    _hasLoaded = false;
    emit(const FriendsState(friends: {}));
    if (userId.isNotEmpty) {
      unawaited(fetch());
    }
  }

  void _onFriendsChanged(Profile profile) {
    final next = {...state.friends};
    if (profile.isFriend) {
      next[profile.id] = _case.applyContactOverlay(profile);
    } else {
      next.remove(profile.id);
    }
    emit(state.copyWith(friends: next));
    _scheduleSilentFetch();
  }

  void _onContactNamesChanged() {
    if (state.friends.isEmpty || isClosed) {
      return;
    }
    final next = {
      for (final e in state.friends.entries)
        e.key: _case.applyContactOverlay(e.value),
    };
    emit(state.copyWith(friends: next));
  }

  void _scheduleSilentFetch() {
    if (isClosed) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_refreshDebounce, () {
      _refreshTimer = null;
      if (!isClosed) {
        unawaited(fetch(showLoading: false, showError: false));
      }
    });
  }
}

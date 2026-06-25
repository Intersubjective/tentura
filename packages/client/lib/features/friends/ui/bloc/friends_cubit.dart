import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/entity/profile.dart';

import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/friends/data/repository/friends_remote_repository.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';

import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'friends_state.dart';

export 'friends_state.dart';

/// Global Cubit
@singleton
class FriendsCubit extends Cubit<FriendsState> {
  FriendsCubit(
    this._capabilityRepository,
    this._invitationRepository,
    this._likeRemoteRepository,
    this._friendsRemoteRepository,
    this._presenceRepository,
    AuthCase _authCase,
    this._effects,
  ) : super(const FriendsState(friends: {})) {
    _authChanges = _authCase.currentAccountChanges().listen(
      _onAuthChanged,
      cancelOnError: false,
    );
    _friendsChanges = _likeRemoteRepository.changes
        .where((e) => e.value is Profile)
        .map((e) => e.value as Profile)
        .listen(_onFriendsChanged, cancelOnError: false);
  }

  final FriendsRemoteRepository _friendsRemoteRepository;

  final CapabilityRepositoryPort _capabilityRepository;

  final InvitationRepository _invitationRepository;

  final LikeRemoteRepository _likeRemoteRepository;

  final PresenceRepository _presenceRepository;

  final UiEffectPort _effects;

  late final StreamSubscription<String> _authChanges;

  late final StreamSubscription<Profile> _friendsChanges;

  @override
  @disposeMethod
  Future<void> close() async {
    await _authChanges.cancel();
    await _friendsChanges.cancel();
    return super.close();
  }

  Future<void> fetch() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final friends = await _friendsRemoteRepository.fetch();
      final friendsById = {for (final e in friends) e.id: e};
      final friendContexts = await _capabilityRepository.fetchFriendContextsBatch(
        subjectIds: friendsById.keys.toList(),
      );
      emit(
        FriendsState(
          friends: friendsById,
          friendContexts: friendContexts,
        ),
      );
      _presenceRepository.watch('friends', friendsById.keys.toSet());
    } catch (e) {
      if (state.friends.isEmpty) {
        emit(state.copyWith(status: StateHasError(e)));
      } else {
        _effects.emit(ShowError(e));
        emit(state.copyWith(status: const StateIsSuccess()));
      }
    }
  }

  Future<void> addFriend(Profile user) =>
      _likeRemoteRepository.setLike(user, amount: 1);

  Future<void> removeFriend(Profile user) =>
      _likeRemoteRepository.setLike(user, amount: 0);

  Future<void> acceptInvitation(String id) => _invitationRepository.accept(id);

  void _onAuthChanged(String userId) {
    _presenceRepository.unwatch('friends');
    // ignore: prefer_const_constructors //
    emit(FriendsState(friends: {}));
    if (userId.isNotEmpty) {
      unawaited(fetch());
    }
  }

  void _onFriendsChanged(Profile profile) {
    emit(state.copyWith(status: StateStatus.isLoading));
    if (profile.isFriend) {
      state.friends[profile.id] = profile;
    } else {
      state.friends.remove(profile.id);
    }
    unawaited(fetch());
  }
}

import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/profile.dart';

import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/friends/data/repository/friends_remote_repository.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';

import 'friends_state.dart';

export 'friends_state.dart';

/// Global Cubit
@singleton
class FriendsCubit extends Cubit<FriendsState> {
  FriendsCubit(
    this._invitationRepository,
    this._likeRemoteRepository,
    this._friendsRemoteRepository,
    AuthCase _authCase,
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

  final InvitationRepository _invitationRepository;

  final LikeRemoteRepository _likeRemoteRepository;

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
      emit(
        FriendsState(
          friends: {for (final e in friends) e.id: e},
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> addFriend(Profile user) =>
      _likeRemoteRepository.setLike(user, amount: 1);

  Future<void> removeFriend(Profile user) =>
      _likeRemoteRepository.setLike(user, amount: 0);

  Future<void> acceptInvitation(String id) => _invitationRepository.accept(id);

  void _onAuthChanged(String userId) {
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
    emit(FriendsState(friends: state.friends));
  }
}

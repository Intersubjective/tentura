import 'package:injectable/injectable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/features/profile/domain/entity/profile.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';

import '../../domain/use_case/friends_case.dart';
import 'friends_state.dart';

export 'friends_state.dart';

@lazySingleton
class FriendsCubit extends Cubit<FriendsState> {
  FriendsCubit(
    this._authCase,
    this._friendsCase,
  ) : super(const FriendsState()) {
    _authChanges.resume();
    _friendsChanges.resume();
  }

  final AuthCase _authCase;
  final FriendsCase _friendsCase;

  late final _authChanges = _authCase.currentAccountChanges.listen(
    (userId) {
      // ignore: prefer_const_constructors
      emit(FriendsState(friends: {}));
      if (userId.isNotEmpty) fetch();
    },
    cancelOnError: false,
  );

  late final _friendsChanges = _friendsCase.friendsChanges.listen(
    (profile) {
      emit(state.setLoading());
      if (profile.isFriend) {
        state.friends[profile.id] = profile;
      } else {
        state.friends.remove(profile.id);
      }
      emit(FriendsState(friends: state.friends));
    },
    cancelOnError: false,
  );

  @override
  @disposeMethod
  Future<void> close() async {
    await _authChanges.cancel();
    await _friendsChanges.cancel();
    return super.close();
  }

  Future<void> fetch() async {
    emit(state.setLoading());
    try {
      final friends = await _friendsCase.fetch();
      emit(FriendsState(
        friends: {
          for (final e in friends) e.id: e,
        },
      ));
    } catch (e) {
      emit(state.setError(e));
    }
  }

  Future<void> addFriend(Profile user) => _friendsCase.addFriend(user);

  Future<void> removeFriend(Profile user) => _friendsCase.removeFriend(user);
}

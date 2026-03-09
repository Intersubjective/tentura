import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/likable.dart';
import 'package:tentura/domain/entity/repository_event.dart';

import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';

import 'like_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'like_state.dart';

/// Global Cubit
@lazySingleton
class LikeCubit extends Cubit<LikeState> {
  LikeCubit(
    AuthCase authCase,
    this._likeRemoteRepository,
  ) : super(
        LikeState(
          likes: {},
          updatedAt: DateTime.timestamp(),
        ),
      ) {
    _authChanges = authCase.currentAccountChanges().listen(
      _onAuthChanges,
      cancelOnError: false,
    );
    _likeChanges = _likeRemoteRepository.changes.listen(
      _onLikeChanged,
      cancelOnError: false,
    );
  }

  final LikeRemoteRepository _likeRemoteRepository;

  late final StreamSubscription<String> _authChanges;

  late final StreamSubscription<RepositoryEvent<Likable>> _likeChanges;

  //
  @override
  @disposeMethod
  Future<void> close() async {
    await _authChanges.cancel();
    await _likeChanges.cancel();
    return super.close();
  }

  //
  //
  Future<void> incrementLike(Likable entity) async {
    try {
      await _likeRemoteRepository.setLike(
        entity,
        amount: (state.likes[entity.id] ?? entity.votes) + 1,
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: StateHasError(e),
        ),
      );
    }
  }

  //
  //
  Future<void> decrementLike(Likable entity) async {
    try {
      await _likeRemoteRepository.setLike(
        entity,
        amount: (state.likes[entity.id] ?? entity.votes) - 1,
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: StateHasError(e),
        ),
      );
    }
  }

  //
  //
  void _onAuthChanges(String id) => emit(
    LikeState(
      likes: {},
      updatedAt: DateTime.timestamp(),
    ),
  );

  //
  //
  void _onLikeChanged(RepositoryEvent<Likable> event) {
    state.likes[event.id] = event.value.votes;
    emit(
      state.copyWith(
        updatedAt: DateTime.timestamp(),
      ),
    );
  }
}

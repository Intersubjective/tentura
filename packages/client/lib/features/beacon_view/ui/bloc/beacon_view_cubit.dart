import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/comment/data/repository/comment_repository.dart';

import '../../data/repository/beacon_view_repository.dart';
import 'beacon_view_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'beacon_view_state.dart';

class BeaconViewCubit extends Cubit<BeaconViewState> {
  BeaconViewCubit({
    required String id,
    required Profile myProfile,
    BeaconRepository? beaconRepository,
    CommentRepository? commentRepository,
    BeaconViewRepository? beaconViewRepository,
  }) : _beaconViewRepository =
           beaconViewRepository ?? GetIt.I<BeaconViewRepository>(),
       _beaconRepository = beaconRepository ?? GetIt.I<BeaconRepository>(),
       _commentRepository = commentRepository ?? GetIt.I<CommentRepository>(),
       super(_idToState(id, myProfile)) {
    unawaited(
      state.hasFocusedComment
          // Show Beacon with one Comment
          ? _fetchBeaconByCommentId()
          // show Beacon with all Comments
          : _fetchBeaconByIdWithComments(),
    );
  }

  final BeaconRepository _beaconRepository;
  final BeaconViewRepository _beaconViewRepository;
  final CommentRepository _commentRepository;

  Future<void> delete(String beaconId) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _beaconRepository.delete(beaconId);
      emit(state.copyWith(status: StateIsNavigating.back));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> toggleEnabled() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _beaconRepository.setEnabled(
        !state.beacon.isEnabled,
        id: state.beacon.id,
      );
      emit(state.copyWith(status: StateStatus.isSuccess));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> showAll() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final comments = await _commentRepository.fetchCommentsByBeaconId(
        state.beacon.id,
      );
      emit(
        state.copyWith(
          focusCommentId: '',
          hasReachedMax: true,
          comments: comments.toList(),
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> addComment(String text) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final comment = await _commentRepository.addComment(
        beaconId: state.beacon.id,
        content: text,
      );
      emit(
        state.copyWith(
          status: StateStatus.isSuccess,
          comments: state.comments
            ..add(comment.copyWith(author: state.myProfile)),
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> _fetchBeaconByIdWithComments([int limit = 3]) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final (:beacon, :comments) = await _beaconViewRepository
          .fetchBeaconByIdWithComments(beaconId: state.beacon.id, limit: limit);
      emit(
        state.copyWith(
          beacon: beacon,
          comments: comments.toList(),
          hasReachedMax: comments.length < limit,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> _fetchBeaconByCommentId() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final (:beacon, :comment) = await _beaconViewRepository
          .fetchBeaconByCommentId(state.focusCommentId);
      emit(
        state.copyWith(
          beacon: beacon,
          comments: [comment],
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  static final _zeroDateTime = DateTime.fromMillisecondsSinceEpoch(0);
  static final _emptyBeacon = Beacon(
    createdAt: _zeroDateTime,
    updatedAt: _zeroDateTime,
  );

  static BeaconViewState _idToState(String id, Profile myProfile) =>
      switch (id) {
        _ when id.startsWith('B') => BeaconViewState(
          beacon: _emptyBeacon.copyWith(id: id),
          myProfile: myProfile,
        ),
        _ when id.startsWith('C') => BeaconViewState(
          beacon: _emptyBeacon,
          focusCommentId: id,
          myProfile: myProfile,
        ),
        _ => BeaconViewState(
          beacon: _emptyBeacon,
          status: StateHasError('Wrong id: $id'),
        ),
      };
}

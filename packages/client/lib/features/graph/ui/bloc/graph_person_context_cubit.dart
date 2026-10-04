import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';

import 'graph_person_context_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'graph_person_context_state.dart';

class GraphPersonContextCubit extends Cubit<GraphPersonContextState> {
  GraphPersonContextCubit({
    required ProfileViewCase profileViewCase,
    required String viewerId,
    this.onProfilePatched,
  }) : _case = profileViewCase,
       _viewerId = viewerId,
       super(const GraphPersonContextState());

  final ProfileViewCase _case;
  final String _viewerId;
  final void Function(Profile profile)? onProfilePatched;

  /// Server profile of the current selection. Callers may pass a partial
  /// profile (Constellation builds one from trust edges only), so the
  /// visibility flags come from this once it arrives.
  Profile? _authoritative;

  void selectProfile(Profile profile, {required bool intentional}) {
    if (isClosed) return;
    final id = profile.id;
    if (id.isEmpty || id == _viewerId) {
      clearSelection();
      return;
    }

    final currentId = state.selectedProfile?.id;
    if (currentId != id) {
      _authoritative = null;
      emit(
        state.copyWith(
          selectedProfile: profile,
          dismissedFocusId: null,
          trustLoading: false,
          trustError: null,
          selectionSequence: state.selectionSequence + 1,
        ),
      );
      unawaited(_loadAuthoritative(id, state.selectionSequence));
      return;
    }
    if (_authoritative case final known? when known.id == id) {
      profile = known;
    }

    if (intentional) {
      emit(
        state.copyWith(
          selectedProfile: profile,
          dismissedFocusId: null,
          trustLoading: false,
          trustError: null,
        ),
      );
      return;
    }

    if (state.dismissedFocusId == id) {
      return;
    }

    emit(state.copyWith(selectedProfile: profile));
  }

  Future<void> _loadAuthoritative(String id, int sequence) async {
    final Profile fetched;
    try {
      fetched = await _case.fetchProfile(id);
    } on Object {
      // Best effort: the caller's profile stays on screen.
      return;
    }
    if (isClosed ||
        fetched.id != id ||
        state.selectedProfile?.id != id ||
        state.selectionSequence != sequence) {
      return;
    }
    _authoritative = fetched;
    emit(state.copyWith(selectedProfile: fetched));
  }

  void dismiss() {
    if (isClosed) return;
    final id = state.selectedProfile?.id;
    if (id == null || id.isEmpty) return;
    emit(
      state.copyWith(
        dismissedFocusId: id,
        trustLoading: false,
        trustError: null,
      ),
    );
  }

  Future<void> trustSelected() async {
    if (isClosed) return;
    final profile = state.selectedProfile;
    if (profile == null) return;

    final aliceId = profile.id;
    final sequence = state.selectionSequence;

    emit(state.copyWith(trustLoading: true, trustError: null));

    try {
      final authoritative = await _case.addFriend(profile);
      onProfilePatched?.call(authoritative);
      if (isClosed) return;
      if (state.selectedProfile?.id == aliceId &&
          state.selectionSequence == sequence) {
        _authoritative = authoritative;
        emit(
          state.copyWith(
            selectedProfile: authoritative,
            trustLoading: false,
            trustError: null,
          ),
        );
      }
    } on Object catch (error) {
      if (isClosed) return;
      if (state.selectedProfile?.id == aliceId &&
          state.selectionSequence == sequence) {
        emit(
          state.copyWith(
            trustLoading: false,
            trustError: error,
          ),
        );
      }
    }
  }

  void clearSelection() {
    if (isClosed) return;
    _authoritative = null;
    emit(
      state.copyWith(
        selectedProfile: null,
        dismissedFocusId: null,
        trustLoading: false,
        trustError: null,
      ),
    );
  }
}

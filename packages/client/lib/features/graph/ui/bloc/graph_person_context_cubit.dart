import 'dart:async';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';

import 'graph_cubit.dart';
import 'graph_person_context_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'graph_person_context_state.dart';

class GraphPersonContextCubit extends Cubit<GraphPersonContextState> {
  GraphPersonContextCubit({
    required ProfileViewCase profileViewCase,
    required GraphCubit graphCubit,
  }) : _case = profileViewCase,
       _graphCubit = graphCubit,
       super(const GraphPersonContextState());

  final ProfileViewCase _case;
  final GraphCubit _graphCubit;

  void selectProfile(Profile profile, {required bool intentional}) {
    if (isClosed) return;
    final id = profile.id;
    if (id.isEmpty || id == _graphCubit.state.me.id) {
      clearSelection();
      return;
    }

    final currentId = state.selectedProfile?.id;
    if (currentId != id) {
      emit(
        state.copyWith(
          selectedProfile: profile,
          dismissedFocusId: null,
          trustLoading: false,
          trustError: null,
          selectionSequence: state.selectionSequence + 1,
        ),
      );
      return;
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
      if (!isClosed) {
        _graphCubit.patchLoadedProfile(authoritative);
      }
      if (isClosed) return;
      if (state.selectedProfile?.id == aliceId &&
          state.selectionSequence == sequence) {
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

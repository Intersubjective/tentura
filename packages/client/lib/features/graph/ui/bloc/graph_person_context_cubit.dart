import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';

import '../../domain/use_case/graph_trust_write_case.dart';
import 'graph_person_context_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'graph_person_context_state.dart';

class GraphPersonContextCubit extends Cubit<GraphPersonContextState> {
  GraphPersonContextCubit({
    required ProfileViewCase profileViewCase,
    required GraphTrustWriteCase trustWriteCase,
    required String viewerId,
    this.onProfilePatched,
  }) : _case = profileViewCase,
       _trustWrites = trustWriteCase,
       _viewerId = viewerId,
       super(const GraphPersonContextState()) {
    _revertSubscription = _trustWrites.reverts.listen(_onRevert);
    _resetSubscription = _trustWrites.resets.listen(_onReset);
  }

  final ProfileViewCase _case;
  final GraphTrustWriteCase _trustWrites;
  late final StreamSubscription<GraphTrustRevert> _revertSubscription;
  late final StreamSubscription<Profile> _resetSubscription;

  Stream<LazyWriteNotice> get lazyWriteNotices => _trustWrites.lazyWriteNotices;
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
          selectedProfile: _trustWrites.overlay(profile),
          dismissedFocusId: null,
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
          selectedProfile: _trustWrites.overlay(profile),
          dismissedFocusId: null,
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
    _authoritative = _trustWrites.overlay(fetched, authoritative: true);
    emit(state.copyWith(selectedProfile: _authoritative));
  }

  void dismiss() {
    if (isClosed) return;
    final id = state.selectedProfile?.id;
    if (id == null || id.isEmpty) return;
    emit(
      state.copyWith(
        dismissedFocusId: id,
        trustError: null,
      ),
    );
  }

  Future<void> trustSelected() => _setTrust(add: true);

  /// Withdraws the viewer's trust (the mini-profile toggle, #140).
  Future<void> untrustSelected() => _setTrust(add: false);

  Future<void> _setTrust({required bool add}) async {
    if (isClosed) return;
    final profile = state.selectedProfile;
    if (profile == null) return;
    _patchTrust(_trustWrites.setTrust(profile, add: add));
  }

  void _patchTrust(Profile profile) {
    _authoritative = profile;
    emit(state.copyWith(selectedProfile: profile, trustError: null));
    onProfilePatched?.call(profile);
  }

  void _onRevert(GraphTrustRevert revert) {
    if (isClosed || !_trustWrites.isCurrentRevert(revert)) return;
    final profile = revert.profile.copyWith(myVote: revert.acknowledgedAmount);
    onProfilePatched?.call(profile);
    if (state.selectedProfile?.id != revert.peerId) {
      emit(state.copyWith(trustError: revert));
      return;
    }
    final selected = state.selectedProfile!.copyWith(
      myVote: revert.acknowledgedAmount,
    );
    _authoritative = selected;
    emit(state.copyWith(selectedProfile: selected, trustError: revert));
  }

  void _onReset(Profile profile) {
    if (isClosed) return;
    onProfilePatched?.call(profile);
    final selected = state.selectedProfile;
    if (selected == null || selected.id != profile.id) return;
    _authoritative = selected.copyWith(myVote: profile.myVote);
    emit(state.copyWith(selectedProfile: _authoritative, trustError: null));
  }

  Future<void> retryTrust([GraphTrustRevert? revert]) async {
    if (isClosed) return;
    final error = revert ?? state.trustError;
    if (error is GraphTrustRevert) {
      final profile = _trustWrites.retry(error);
      if (profile == null) return;
      if (state.selectedProfile?.id == profile.id) {
        _patchTrust(state.selectedProfile!.copyWith(myVote: profile.myVote));
      } else {
        if (identical(state.trustError, error)) {
          emit(state.copyWith(trustError: null));
        }
        onProfilePatched?.call(profile);
      }
    }
  }

  @override
  Future<void> close() async {
    await _revertSubscription.cancel();
    await _resetSubscription.cancel();
    await super.close();
  }

  void clearSelection() {
    if (isClosed) return;
    _authoritative = null;
    emit(
      state.copyWith(
        selectedProfile: null,
        dismissedFocusId: null,
        trustError: null,
      ),
    );
  }
}

import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../domain/use_case/profile_view_case.dart';

import 'profile_view_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'profile_view_state.dart';

class ProfileViewCubit extends Cubit<ProfileViewState> {
  ProfileViewCubit({
    required String id,
    ProfileViewCase? profileViewCase,
    UiEffectPort? effects,
  }) : _profileId = id,
       _case = profileViewCase ?? GetIt.I<ProfileViewCase>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(switch (id) {
         _ when id.startsWith('U') => ProfileViewState(
           profile: Profile(id: id),
         ),
         _ => ProfileViewState(loadError: 'Wrong id: $id'),
       }) {
    if (state.loadError != null) {
      _effects.emit(ShowError(state.loadError!));
      return;
    }
    _projectionSub = _case
        .projectionChanges(id)
        .listen(
          (_) => _scheduleSilentFetch(),
          cancelOnError: false,
        );
    unawaited(fetch());
  }

  final String _profileId;
  final ProfileViewCase _case;
  final UiEffectPort _effects;
  StreamSubscription<void>? _projectionSub;
  Timer? _refreshTimer;
  int _fetchSequence = 0;
  bool _hasLoaded = false;

  static const _refreshDebounce = Duration(milliseconds: 100);

  void _showSnackError(Object error) {
    _effects.emit(ShowError(error));
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  @override
  Future<void> close() async {
    _refreshTimer?.cancel();
    await _projectionSub?.cancel();
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
      final snapshot = await _case.load(_profileId);
      if (isClosed || sequence != _fetchSequence) return;
      emit(
        ProfileViewState(
          profile: snapshot.profile,
          cues: snapshot.cues,
        ),
      );
      _hasLoaded = true;
    } catch (e) {
      if (isClosed || sequence != _fetchSequence) return;
      if (!_hasLoaded) {
        emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
      } else {
        emit(state.copyWith(status: const StateIsSuccess()));
      }
      if (showError) _effects.emit(ShowError(e));
    }
  }

  Future<void> addFriend() => _setRelationship(add: true);

  Future<void> removeFriend() => _setRelationship(add: false);

  Future<void> _setRelationship({required bool add}) async {
    final sequence = ++_fetchSequence;
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final profile = add
          ? await _case.addFriend(state.profile)
          : await _case.removeFriend(state.profile);
      if (isClosed || sequence != _fetchSequence) return;
      emit(
        state.copyWith(
          profile: profile,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      _showSnackError(e);
    }
  }

  void updatePrivateLabels(List<String> slugs) {
    emit(
      state.copyWith(
        cues: state.cues.copyWith(privateLabels: slugs),
      ),
    );
  }

  void updateViewerVisible(List<CapabilityWithSource> viewerVisible) {
    emit(
      state.copyWith(cues: state.cues.copyWith(viewerVisible: viewerVisible)),
    );
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

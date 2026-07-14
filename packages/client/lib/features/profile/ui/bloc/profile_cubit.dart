import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';

import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../domain/port/profile_repository_port.dart';
import 'profile_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'package:get_it/get_it.dart';

export 'profile_state.dart';

/// Global Cubit
@singleton
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({
    required this._accountCase,
    required AuthCase authCase,
    required ProfileRepositoryPort profileRepository,
    required RealtimeSyncCase realtimeSyncCase,
    required this._effects,
  }) : _profileRepository = profileRepository,
       super(const ProfileState()) {
    _authChanges = authCase.currentAccountChanges().listen(
      _onAuthChanges,
      cancelOnError: false,
    );
    _profileChanges = profileRepository.changes.listen(
      _onProfileChanges,
      cancelOnError: false,
    );
    _realtimeProfileChanges = realtimeSyncCase
        .changesFor(const {RealtimeEntityKind.profile})
        .listen(_onRealtimeProfileChanged, cancelOnError: false);
    _catchUps = realtimeSyncCase.catchUps.listen(
      _onCatchUp,
      cancelOnError: false,
    );
  }

  final AccountCase _accountCase;

  final ProfileRepositoryPort _profileRepository;

  final UiEffectPort _effects;

  late final StreamSubscription<String> _authChanges;

  late final StreamSubscription<RepositoryEvent<Profile>> _profileChanges;

  late final StreamSubscription<RealtimeEntityChange> _realtimeProfileChanges;

  late final StreamSubscription<RealtimeCatchUp> _catchUps;

  static const _refreshDebounce = Duration(milliseconds: 100);
  Timer? _refreshTimer;
  int _fetchSequence = 0;
  int _accountSequence = 0;

  //
  //
  @disposeMethod
  Future<void> dispose() async {
    _refreshTimer?.cancel();
    await _authChanges.cancel();
    await _profileChanges.cancel();
    await _realtimeProfileChanges.cancel();
    await _catchUps.cancel();
    return super.close();
  }

  //
  //
  Future<void> fetch({
    bool showLoading = true,
    bool showError = true,
  }) async {
    final profileId = state.profile.id;
    if (profileId.isEmpty) return;
    final sequence = ++_fetchSequence;
    if (showLoading) {
      emit(state.copyWith(status: StateStatus.isLoading));
    }
    try {
      final profile = await _profileRepository.fetchById(profileId);
      if (isClosed ||
          sequence != _fetchSequence ||
          state.profile.id != profileId) {
        return;
      }
      emit(ProfileState(profile: profile));
    } catch (e) {
      if (isClosed ||
          sequence != _fetchSequence ||
          state.profile.id != profileId) {
        return;
      }
      if (showError) _effects.emit(ShowError(e));
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  //
  //
  Future<void> delete() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _profileRepository.delete(state.profile.id);
      _effects.emit(const NavigatePush(kPathSignIn));
      emit(const ProfileState());
    } catch (e) {
      _effects.emit(ShowError(e));
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  //
  //
  Future<void> _onAuthChanges(String id) async {
    _refreshTimer?.cancel();
    final accountSequence = ++_accountSequence;
    _fetchSequence++;
    if (id.isEmpty) {
      emit(const ProfileState());
      return;
    }
    final account = await _accountCase.getAccountById(id);
    if (isClosed || accountSequence != _accountSequence) return;
    emit(
      ProfileState(
        profile: account != null
            ? AccountCase.fromAccountEntity(account)
            : Profile(id: id),
      ),
    );
    await fetch();
  }

  //
  //
  void _onProfileChanges(RepositoryEvent<Profile> event) => switch (event) {
    RepositoryEventUpdate<Profile>(value: final profile)
        when profile.id == state.profile.id =>
      emit(ProfileState(profile: profile)),
    _ => null,
  };

  void _onRealtimeProfileChanged(RealtimeEntityChange change) {
    if (change.aggregateId == state.profile.id) {
      _scheduleSilentFetch();
    }
  }

  void _onCatchUp(RealtimeCatchUp _) {
    if (state.profile.id.isNotEmpty) _scheduleSilentFetch();
  }

  void _scheduleSilentFetch() {
    if (isClosed || state.profile.id.isEmpty) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_refreshDebounce, () {
      _refreshTimer = null;
      if (!isClosed) {
        unawaited(fetch(showLoading: false, showError: false));
      }
    });
  }
}

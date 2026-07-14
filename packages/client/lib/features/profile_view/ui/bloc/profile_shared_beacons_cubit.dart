import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/ui/bloc/state_base.dart';

import '../../data/repository/profile_shared_beacons_repository.dart';
import '../../domain/use_case/profile_shared_beacons_case.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export '../../data/repository/profile_shared_beacons_repository.dart'
    show
        ProfileCoHelpOfferedEntry,
        ProfileForwardedBeaconEntry,
        ProfileSharedBeaconsData,
        TargetBeaconReaction;

part 'profile_shared_beacons_cubit.freezed.dart';

@freezed
abstract class ProfileSharedBeaconsState extends StateBase
    with _$ProfileSharedBeaconsState {
  const factory ProfileSharedBeaconsState({
    @Default(StateIsSuccess()) StateStatus status,
    ProfileSharedBeaconsData? data,
    Object? loadError,
  }) = _ProfileSharedBeaconsState;

  const ProfileSharedBeaconsState._();

  bool get hasError => loadError != null;
}

class ProfileSharedBeaconsCubit extends Cubit<ProfileSharedBeaconsState> {
  ProfileSharedBeaconsCubit({
    required this._meId,
    required this._targetId,
    ProfileSharedBeaconsCase? profileSharedBeaconsCase,
  }) : _case = profileSharedBeaconsCase ?? GetIt.I<ProfileSharedBeaconsCase>(),
       super(const ProfileSharedBeaconsState()) {
    _projectionSub = _case.projectionChanges.listen(
      (_) => _scheduleSilentFetch(),
      cancelOnError: false,
    );
    unawaited(fetch());
  }

  final String _meId;
  final String _targetId;
  final ProfileSharedBeaconsCase _case;
  late final StreamSubscription<void> _projectionSub;
  Timer? _refreshTimer;
  int _fetchSequence = 0;
  bool _hasLoaded = false;

  static const _refreshDebounce = Duration(milliseconds: 100);

  @override
  Future<void> close() async {
    _refreshTimer?.cancel();
    await _projectionSub.cancel();
    return super.close();
  }

  Future<void> fetch({
    bool showLoading = true,
  }) async {
    final sequence = ++_fetchSequence;
    if (showLoading) {
      emit(state.copyWith(status: StateStatus.isLoading));
    }
    try {
      final data = await _case.load(meId: _meId, targetId: _targetId);
      if (isClosed || sequence != _fetchSequence) return;
      emit(
        state.copyWith(
          status: StateStatus.isSuccess,
          data: data,
          loadError: null,
        ),
      );
      _hasLoaded = true;
    } catch (e) {
      if (isClosed || sequence != _fetchSequence) return;
      emit(
        state.copyWith(
          loadError: _hasLoaded ? null : e,
          status: const StateIsSuccess(),
        ),
      );
    }
  }

  void _scheduleSilentFetch() {
    if (isClosed) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_refreshDebounce, () {
      _refreshTimer = null;
      if (!isClosed) unawaited(fetch(showLoading: false));
    });
  }
}

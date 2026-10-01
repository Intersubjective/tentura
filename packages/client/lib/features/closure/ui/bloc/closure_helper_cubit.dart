import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/features/closure/domain/closure_exception.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/ui/bloc/state_base.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

part 'closure_helper_cubit.freezed.dart';

/// Server `ClosureEpochStatus.evaluating`.
const kClosureStatusEvaluating = 0;

/// `ClosureState.inCalcText` codes.
const kClosureInCalcCounted = 'counted';
const kClosureInCalcDiffers = 'differs';

@freezed
abstract class ClosureHelperState extends StateBase with _$ClosureHelperState {
  const factory ClosureHelperState({
    @Default(StateIsLoading()) StateStatus status,
    ClosureState? data,
    Object? loadError,

    /// Colleague whose support the server released on the last press (U56).
    String? releasedId,

    /// Last failed write; [noticeTick] changes with every new one.
    Object? notice,
    @Default(0) int noticeTick,
  }) = _ClosureHelperState;

  const ClosureHelperState._();
}

class ClosureHelperCubit extends Cubit<ClosureHelperState> {
  ClosureHelperCubit(
    this._case, {
    required this.beaconId,
    required this.viewerId,
    required this.author,
  }) : super(const ClosureHelperState()) {
    unawaited(fetch());
  }

  factory ClosureHelperCubit.fromGetIt({
    required String beaconId,
    required String viewerId,
    required ClosureMember author,
  }) => ClosureHelperCubit(
    GetIt.I<ClosureCase>(),
    beaconId: beaconId,
    viewerId: viewerId,
    author: author,
  );

  final ClosureCase _case;
  final String beaconId;
  final String viewerId;
  final ClosureMember author;

  /// Everyone on the roster except the viewer.
  List<ClosureMember> get colleagues => [
    for (final m in state.data?.members ?? const <ClosureMember>[])
      if (m.id != viewerId) m,
  ];

  /// Supporting needs a choice: at least two colleagues, and the viewer must
  /// be a voter of an evaluating epoch.
  bool get canVote {
    final data = state.data;
    return data != null &&
        data.role == ClosureRole.voter &&
        data.status == kClosureStatusEvaluating &&
        colleagues.length >= 2;
  }

  Future<void> fetch() async {
    emit(state.copyWith(status: StateStatus.isLoading, loadError: null));
    try {
      final data = await _case.fetchState(beaconId);
      if (isClosed) return;
      emit(state.copyWith(status: StateStatus.isSuccess, data: data));
    } on Object catch (e) {
      if (isClosed) return;
      emit(state.copyWith(status: StateStatus.isSuccess, loadError: e));
    }
  }

  Future<void> toggleSupport(String targetId, {required bool on}) => _write(
    (epoch) => _case.toggleSupport(
      beaconId: beaconId,
      expectedEpoch: epoch,
      targetId: targetId,
      on: on,
    ),
  );

  Future<void> done() => _write((epoch) async {
    await _case.done(beaconId: beaconId, expectedEpoch: epoch);
    return null;
  });

  Future<void> skip() => _write((epoch) async {
    await _case.skip(beaconId: beaconId, expectedEpoch: epoch);
    return null;
  });

  Future<void> setMark(String targetId, {required bool on}) =>
      _write((epoch) async {
        await _case.setMark(
          beaconId: beaconId,
          expectedEpoch: epoch,
          targetId: targetId,
          on: on,
        );
        return null;
      });

  /// Runs a write at the loaded epoch; [action] returns the released
  /// colleague id (support presses only). Reloads afterwards.
  Future<void> _write(Future<String?> Function(int epoch) action) async {
    final data = state.data;
    if (data == null) return;
    try {
      final released = await action(data.epoch);
      if (isClosed) return;
      emit(state.copyWith(releasedId: released));
    } on Object catch (e) {
      if (isClosed) return;
      emit(state.copyWith(notice: e, noticeTick: state.noticeTick + 1));
      // A stale epoch means the screen is out of date: reload it.
      if (e is! ClosureStaleEpochException) return;
    }
    await fetch();
  }
}

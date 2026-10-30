import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/closure/domain/closure_exception.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'closure_review_hints.dart';

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

    /// The Request left the final check (closed, or reopened) while this
    /// page was open. The page returns to the Request, as the author's does.
    @Default(false) bool leftReview,
  }) = _ClosureHelperState;

  const ClosureHelperState._();
}

class ClosureHelperCubit extends Cubit<ClosureHelperState> {
  ClosureHelperCubit(
    this._case, {
    required this.beaconId,
    required this.viewerId,
    required this.author,
    Stream<RepositoryEvent<Beacon>>? requestChanges,
    Future<BeaconStatus?> Function()? readBeaconStatus,
  }) : super(const ClosureHelperState()) {
    _requestChanges = listenForClosureReviewHints(
      changes: requestChanges,
      beaconId: beaconId,
      isClosed: () => isClosed,
      readBeaconStatus: readBeaconStatus,
      reload: fetch,
      onReloaded: _onReviewHint,
    );
    unawaited(fetch());
  }

  factory ClosureHelperCubit.fromGetIt({
    required String beaconId,
    required String viewerId,
    required ClosureMember author,
  }) {
    final beacons = GetIt.I<BeaconRepository>();
    return ClosureHelperCubit(
      GetIt.I<ClosureCase>(),
      beaconId: beaconId,
      viewerId: viewerId,
      author: author,
      requestChanges: beacons.changes,
      readBeaconStatus: () async {
        try {
          return (await beacons.fetchBeaconById(beaconId)).status;
        } on Object {
          return null;
        }
      },
    );
  }

  final ClosureCase _case;
  final String beaconId;
  final String viewerId;
  final ClosureMember author;

  StreamSubscription<RepositoryEvent<Beacon>>? _requestChanges;
  var _loadGeneration = 0;

  void _onReviewHint({required bool beaconLeftReview}) {
    if (isClosed || state.leftReview) return;
    final stillEvaluating =
        state.data == null || state.data!.status == kClosureStatusEvaluating;
    if (beaconLeftReview && stillEvaluating) {
      emit(state.copyWith(leftReview: true));
      return;
    }
    if (state.data != null && state.data!.status != kClosureStatusEvaluating) {
      emit(state.copyWith(leftReview: true));
    }
  }

  @override
  Future<void> close() async {
    await _requestChanges?.cancel();
    return super.close();
  }

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
    final generation = ++_loadGeneration;
    emit(state.copyWith(status: StateStatus.isLoading, loadError: null));
    try {
      final data = await _case.fetchState(beaconId);
      if (isClosed || generation != _loadGeneration) return;
      emit(state.copyWith(status: StateStatus.isSuccess, data: data));
    } on Object catch (e) {
      if (isClosed || generation != _loadGeneration) return;
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

import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/features/closure/domain/closure_exception.dart';
import 'package:tentura/features/closure/domain/entity/closure_outcome.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/ui/bloc/state_base.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

part 'closure_author_cubit.freezed.dart';

/// Slider granularity and floor of the hand-made split (percent).
const kClosureSplitStep = 5;

/// Most people the author may split by hand.
const kClosureSplitMaxPeople = 20;

/// Extensions allowed per closure attempt.
const kClosureMaxExtensions = 2;

@freezed
abstract class ClosureAuthorState extends StateBase with _$ClosureAuthorState {
  const factory ClosureAuthorState({
    @Default(StateIsLoading()) StateStatus status,
    ClosureState? data,

    /// Non-null while the split sliders are unlocked: helper id -> percent.
    Map<String, int>? draft,
    Object? loadError,

    /// Last failed write; [noticeTick] changes with every new one.
    Object? notice,
    @Default(0) int noticeTick,
  }) = _ClosureAuthorState;

  const ClosureAuthorState._();

  /// Members the author did not mark «Не выполнено» (set A).
  List<String> get splitIds => data == null
      ? const []
      : [
          for (final m in data!.members)
            if (data!.outcomes?[m.id] != ClosureOutcome.notDone) m.id,
        ];

  bool get splitAvailable => splitIds.length <= kClosureSplitMaxPeople;
}

class ClosureAuthorCubit extends Cubit<ClosureAuthorState> {
  ClosureAuthorCubit(
    this._case, {
    required this.beaconId,
  }) : super(const ClosureAuthorState()) {
    unawaited(fetch());
  }

  factory ClosureAuthorCubit.fromGetIt({required String beaconId}) =>
      ClosureAuthorCubit(GetIt.I<ClosureCase>(), beaconId: beaconId);

  final ClosureCase _case;
  final String beaconId;

  Future<void> fetch() async {
    emit(state.copyWith(status: StateStatus.isLoading, loadError: null));
    try {
      final data = await _case.fetchState(beaconId);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: StateStatus.isSuccess,
          data: data,
          draft: state.draft == null ? null : _revalidated(state.draft, data),
        ),
      );
    } on Object catch (e) {
      if (isClosed) return;
      emit(state.copyWith(status: StateStatus.isSuccess, loadError: e));
    }
  }

  Future<void> setOutcome(String helperId, ClosureOutcome? outcome) => _write(
    (epoch) => _case.saveOutcome(
      beaconId: beaconId,
      expectedEpoch: epoch,
      helperId: helperId,
      outcome: outcome,
    ),
  );

  Future<void> setMark(String targetId, {required bool on}) => _write(
    (epoch) => _case.setMark(
      beaconId: beaconId,
      expectedEpoch: epoch,
      targetId: targetId,
      on: on,
    ),
  );

  Future<void> saveStory(String body) => _write(
    (epoch) =>
        _case.saveStory(beaconId: beaconId, expectedEpoch: epoch, body: body),
  );

  Future<void> closeNow() => _write(
    (epoch) => _case.closeNow(beaconId: beaconId, expectedEpoch: epoch),
  );

  Future<void> extend() => _write(
    (epoch) => _case.extendClosure(beaconId: beaconId, expectedEpoch: epoch),
  );

  Future<void> reopen() => _write(
    (epoch) => _case.reopen(beaconId: beaconId, expectedEpoch: epoch),
  );

  /// Unlocks the sliders, starting from the saved split or equal shares.
  void unlockSplit() {
    final data = state.data;
    if (data == null || !state.splitAvailable) return;
    emit(state.copyWith(draft: _revalidated(data.split, data)));
  }

  /// Moves [id] to [percent]; the others absorb the difference in steps of 5.
  void changeDraft(String id, int percent) {
    final draft = state.draft;
    if (draft == null || !draft.containsKey(id)) return;
    emit(state.copyWith(draft: rebalanceSplit(draft, id, percent)));
  }

  Future<void> saveSplit() {
    final draft = state.draft;
    if (draft == null) return Future.value();
    return _write(
      (epoch) => _case.saveAuthorSplit(
        beaconId: beaconId,
        expectedEpoch: epoch,
        split: Map.of(draft),
      ),
      clearDraft: true,
    );
  }

  Future<void> resetSplit() => _write(
    (epoch) => _case.saveAuthorSplit(
      beaconId: beaconId,
      expectedEpoch: epoch,
      split: null,
    ),
    clearDraft: true,
  );

  Future<void> _write(
    Future<void> Function(int epoch) action, {
    bool clearDraft = false,
  }) async {
    final data = state.data;
    if (data == null) return;
    try {
      await action(data.epoch);
      if (isClosed) return;
      if (clearDraft) emit(state.copyWith(draft: null));
    } on ClosureStaleEpochException catch (e) {
      if (isClosed) return;
      emit(state.copyWith(notice: e, noticeTick: state.noticeTick + 1));
    } on Object catch (e) {
      if (isClosed) return;
      emit(state.copyWith(notice: e, noticeTick: state.noticeTick + 1));
      return;
    }
    await fetch();
  }
}

/// Keeps [draft] only while it still covers exactly set A and adds up to 100;
/// otherwise falls back to the saved split or equal shares.
Map<String, int>? _revalidated(Map<String, int>? draft, ClosureState data) {
  final ids = [
    for (final m in data.members)
      if (data.outcomes?[m.id] != ClosureOutcome.notDone) m.id,
  ];
  if (ids.isEmpty) return null;
  bool fits(Map<String, int>? m) =>
      m != null &&
      m.length == ids.length &&
      ids.every(m.containsKey) &&
      m.values.fold<int>(0, (a, b) => a + b) == 100 &&
      m.values.every(
        (v) => v >= kClosureSplitStep && v % kClosureSplitStep == 0,
      );
  if (fits(draft)) return draft;
  if (fits(data.split)) return {for (final id in ids) id: data.split![id]!};
  return equalSplit(ids);
}

/// Equal shares in steps of 5 that add up to 100 (remainder to the first ids).
Map<String, int> equalSplit(List<String> ids) {
  const units = 100 ~/ kClosureSplitStep;
  final base = units ~/ ids.length;
  final extra = units % ids.length;
  return {
    for (var i = 0; i < ids.length; i++)
      ids[i]: (base + (i < extra ? 1 : 0)) * kClosureSplitStep,
  };
}

/// Pure slider arithmetic: set [id] to [percent] (rounded to 5, clamped so the
/// others keep at least 5 each) and move the difference through the others.
Map<String, int> rebalanceSplit(
  Map<String, int> split,
  String id,
  int percent,
) {
  final n = split.length;
  final max = 100 - kClosureSplitStep * (n - 1);
  final target = ((percent / kClosureSplitStep).round() * kClosureSplitStep)
      .clamp(
        kClosureSplitStep,
        max,
      );
  final next = Map<String, int>.of(split);
  var delta = target - split[id]!;
  next[id] = target;
  final others = [
    for (final k in split.keys)
      if (k != id) k,
  ];
  while (delta != 0 && others.isNotEmpty) {
    if (delta > 0) {
      // Take from the largest share that is still above the floor.
      String? pick;
      for (final k in others) {
        if (next[k]! > kClosureSplitStep &&
            (pick == null || next[k]! > next[pick]!)) {
          pick = k;
        }
      }
      if (pick == null) break;
      next[pick] = next[pick]! - kClosureSplitStep;
      delta -= kClosureSplitStep;
    } else {
      var pick = others.first;
      for (final k in others) {
        if (next[k]! < next[pick]!) pick = k;
      }
      next[pick] = next[pick]! + kClosureSplitStep;
      delta += kClosureSplitStep;
    }
  }
  return next;
}

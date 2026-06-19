import 'package:freezed_annotation/freezed_annotation.dart';

import 'coordination_item.dart';

part 'coordination_responsibility.freezed.dart';

/// Per-kind open/new counts for the beacon YOU responsibility line.
@freezed
abstract class CoordinationResponsibilityKindCounts
    with _$CoordinationResponsibilityKindCounts {
  const factory CoordinationResponsibilityKindCounts({
    required CoordinationItemKind kind,
    @Default(0) int open,
    @Default(0) int newCount,
  }) = _CoordinationResponsibilityKindCounts;

  const CoordinationResponsibilityKindCounts._();

  bool get hasOpen => open > 0;
}

@freezed
abstract class CoordinationResponsibility with _$CoordinationResponsibility {
  const factory CoordinationResponsibility({
    required String beaconId,
    @Default(0) int askOpen,
    @Default(0) int askNew,
    @Default(0) int promiseOpen,
    @Default(0) int promiseNew,
    @Default(0) int blockerOpen,
    @Default(0) int blockerNew,
    @Default(0) int reviewOpen,
    @Default(0) int reviewNew,
    @Default(0) int othersOpenCount,
  }) = _CoordinationResponsibility;

  const CoordinationResponsibility._();

  bool get hasAny =>
      askOpen + promiseOpen + blockerOpen + reviewOpen > 0;

  int get totalNew => askNew + promiseNew + blockerNew + reviewNew;

  /// Fixed display order: asks, promises, blockers, reviews.
  List<CoordinationResponsibilityKindCounts> get orderedEntries {
    final out = <CoordinationResponsibilityKindCounts>[];
    if (askOpen > 0) {
      out.add(CoordinationResponsibilityKindCounts(
        kind: CoordinationItemKind.ask,
        open: askOpen,
        newCount: askNew,
      ));
    }
    if (promiseOpen > 0) {
      out.add(CoordinationResponsibilityKindCounts(
        kind: CoordinationItemKind.promise,
        open: promiseOpen,
        newCount: promiseNew,
      ));
    }
    if (blockerOpen > 0) {
      out.add(CoordinationResponsibilityKindCounts(
        kind: CoordinationItemKind.blocker,
        open: blockerOpen,
        newCount: blockerNew,
      ));
    }
    if (reviewOpen > 0) {
      out.add(CoordinationResponsibilityKindCounts(
        kind: CoordinationItemKind.resolution,
        open: reviewOpen,
        newCount: reviewNew,
      ));
    }
    return out;
  }

  CoordinationResponsibility withNewCountsCleared() => copyWith(
        askNew: 0,
        promiseNew: 0,
        blockerNew: 0,
        reviewNew: 0,
      );
}

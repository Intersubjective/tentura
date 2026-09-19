import 'package:freezed_annotation/freezed_annotation.dart';

part 'attention_summary.freezed.dart';

@freezed
abstract class AttentionSummary with _$AttentionSummary {
  const factory AttentionSummary({
    @Default(0) int unreadTotal,
    @Default(0) int needsYouTotal,
  }) = _AttentionSummary;
}

@freezed
abstract class AttentionSurfaceSummary with _$AttentionSurfaceSummary {
  const factory AttentionSurfaceSummary({
    required int activityUnreadTotal,
    required int myWorkUnreadTotal,
    required int needsYouTotal,

    /// §6 `my desk.dot` — an owned Request has an uncleared optional event or
    /// uncleared outcome. Computed by the server from the same predicates its
    /// lists compose (M1); never re-derived here from a total.
    @Default(false) bool myDeskDot,

    /// §6 `my desk.count` — live obligations on owned Requests, summed by the
    /// server from the same predicate its myWork list composes (M1).
    ///
    /// A field of its own, not [needsYouTotal] renamed: that total is the
    /// legacy unscoped count and keeps its meaning until U18.
    @Default(0) int myDeskCount,

    /// §6 `for you.dot` — dismissible attention, a pending forward or a
    /// pending prompt.
    ///
    /// There is no `forYouCount` and there must not be one: §6 says
    /// `for you.count = never`, and the absent field is what makes that
    /// structural instead of a convention a widget can break.
    @Default(false) bool forYouDot,
  }) = _AttentionSurfaceSummary;
}

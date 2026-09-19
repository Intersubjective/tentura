import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';

part 'home_attention_state.freezed.dart';

/// Presentation projection for attention markers on the home surfaces.
///
/// The candidate sets are successful client surface snapshots, not domain
/// authority. The unread ids come from the attention application boundary.
@freezed
abstract class HomeAttentionState with _$HomeAttentionState {
  const factory HomeAttentionState({
    @Default({}) Set<String> inboxBeaconIds,
    @Default({}) Set<String> myWorkBeaconIds,
    @Default({}) Set<String> unreadBeaconIds,
    @Default(false) bool inboxLoaded,
    @Default(false) bool myWorkLoaded,
    @Default(false) bool markerQueryComplete,
    @Default(HomeTab.work) HomeTab activeHomeTab,
    @Default(0) int activityUnreadTotal,
    @Default(0) int myWorkUnreadTotal,
    @Default(0) int surfaceNeedsYouTotal,
    @Default(false) bool surfaceSummaryLoaded,
  }) = _HomeAttentionState;

  const HomeAttentionState._();

  bool get projectionReady =>
      inboxLoaded && myWorkLoaded && markerQueryComplete;

  /// My Work wins if stale client snapshots briefly contain the same Beacon.
  Set<String> get effectiveInboxBeaconIds =>
      inboxBeaconIds.difference(myWorkBeaconIds);

  Set<String> get inboxMarkerIds => projectionReady
      ? unreadBeaconIds.intersection(effectiveInboxBeaconIds)
      : const {};

  Set<String> get myWorkMarkerIds => projectionReady
      ? unreadBeaconIds.intersection(myWorkBeaconIds)
      : const {};

  bool isInboxBeaconMarked(String beaconId) =>
      inboxMarkerIds.contains(beaconId);

  bool isMyWorkBeaconMarked(String beaconId) =>
      myWorkMarkerIds.contains(beaconId);

  /// Contract §6: indicators do not hide because the tab is currently open,
  /// and the dot is never gated on the number. Both suppressions lived here
  /// until U14c; [activeHomeTab] is no longer an input to any indicator.
  bool get hasInboxDot => inboxMarkerIds.isNotEmpty;

  bool get hasMyWorkDot => myWorkMarkerIds.isNotEmpty;

  /// Activity nav is a dot only — For You never carries a count (§6).
  bool get showRedesignActivityUnreadDot =>
      surfaceSummaryLoaded && surfaceDotFromTotal(activityUnreadTotal);

  /// Live obligation receipts on My Work (§6 `my desk.count`).
  bool get showRedesignMyWorkObligationBadge =>
      surfaceSummaryLoaded && surfaceCountFromTotal(surfaceNeedsYouTotal) > 0;

  /// Active optional attention on My Work (§6 `my desk.dot`). Independent of
  /// the number beside it: a Request with both contributes to both.
  bool get showRedesignMyWorkUnreadDot =>
      surfaceSummaryLoaded && surfaceDotFromTotal(myWorkUnreadTotal);
}

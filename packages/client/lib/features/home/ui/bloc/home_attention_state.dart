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

    /// §6 `my desk.dot` / `for you.dot`, as the server computed them from the
    /// predicates behind the lists (M1). They are booleans and not totals on
    /// purpose: §6 states a dot as a membership question, and a total is the
    /// answer to a different one.
    @Default(false) bool surfaceMyDeskDot,
    @Default(false) bool surfaceForYouDot,
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

  /// §6 `for you.dot` — any dismissible attention, pending forward or pending
  /// prompt. Activity nav is a dot only; For You never carries a count (§6),
  /// and there is no state field one could be rendered from.
  ///
  /// Until U15R-d this read `activityUnreadTotal`, which is neither: it
  /// counted Activity-surface obligations and saw neither the outcome rows
  /// nor the pinned decision zone.
  bool get showRedesignActivityUnreadDot =>
      surfaceSummaryLoaded && surfaceForYouDot;

  /// §6 `my desk.count` — live obligations on owned Requests.
  ///
  /// Still the legacy unscoped total: U15R-d found that scoping it to the
  /// myWork surface would drop beacon-less live obligations out of every
  /// indicator §6 defines, and left the gap for the contract owner rather
  /// than widening a predicate to absorb it.
  bool get showRedesignMyWorkObligationBadge =>
      surfaceSummaryLoaded && surfaceCountFromTotal(surfaceNeedsYouTotal) > 0;

  /// §6 `my desk.dot` — an owned Request has an uncleared optional event or
  /// uncleared outcome. Independent of the number beside it: a Request with
  /// both contributes to both.
  ///
  /// Until U15R-d this read `myWorkUnreadTotal`, which includes live
  /// obligations — so an obligation-only Request lit the optional dot.
  bool get showRedesignMyWorkUnreadDot =>
      surfaceSummaryLoaded && surfaceMyDeskDot;
}

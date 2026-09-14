import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/app/router/home_tab_branches.dart';

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

  bool get hasInboxDot =>
      activeHomeTab != HomeTab.inbox && inboxMarkerIds.isNotEmpty;

  bool get hasMyWorkDot =>
      activeHomeTab != HomeTab.work && myWorkMarkerIds.isNotEmpty;

  /// Activity nav is a dot only, hidden on the active tab.
  bool get showRedesignActivityUnreadDot =>
      surfaceSummaryLoaded &&
      activityUnreadTotal > 0 &&
      activeHomeTab != HomeTab.inbox;

  /// Live obligation receipts on My Work; visible on active tab.
  bool get showRedesignMyWorkObligationBadge =>
      surfaceSummaryLoaded && surfaceNeedsYouTotal > 0;

  /// Unseen My Work receipts when no live obligations remain.
  bool get showRedesignMyWorkUnreadDot =>
      surfaceSummaryLoaded &&
      surfaceNeedsYouTotal == 0 &&
      myWorkUnreadTotal > 0 &&
      activeHomeTab != HomeTab.work;
}

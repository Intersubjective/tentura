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
    @Default(0) int inboxTriageCount,
    @Default(0) int myWorkObligationCount,
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

  /// Needs-me triage count for the Activity nav badge (Watching excluded).
  ///
  /// Stays visible on the active tab: this is remaining work, not unseen.
  bool get showInboxTriageBadge => inboxLoaded && inboxTriageCount > 0;

  /// Unread marker dot when no pending triage items are shown on the icon.
  bool get showInboxUnreadDot =>
      inboxTriageCount == 0 && hasInboxDot;

  bool get hasMyWorkDot =>
      activeHomeTab != HomeTab.work && myWorkMarkerIds.isNotEmpty;

  /// Live obligation receipt count for the My Work nav badge (not unseen-based).
  ///
  /// Stays visible on the active tab: this is remaining work, not unseen.
  bool get showMyWorkObligationBadge => myWorkObligationCount > 0;

  /// Work / Activity redesign (D5): Activity nav is a dot only, hidden on tab.
  bool get showRedesignActivityUnreadDot =>
      surfaceSummaryLoaded &&
      activityUnreadTotal > 0 &&
      activeHomeTab != HomeTab.inbox;

  /// Redesign (D4): live obligation receipts on My Work; visible on active tab.
  bool get showRedesignMyWorkObligationBadge =>
      surfaceSummaryLoaded && surfaceNeedsYouTotal > 0;

  /// Redesign: unseen My Work receipts when no live obligations remain.
  bool get showRedesignMyWorkUnreadDot =>
      surfaceSummaryLoaded &&
      surfaceNeedsYouTotal == 0 &&
      myWorkUnreadTotal > 0 &&
      activeHomeTab != HomeTab.work;
}
